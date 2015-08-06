require 'open3'
require 'filesize'
require 'chronic_duration'

module Fireworks
  class BlockDevice
    attr_reader :device, :threads, :interval

    def initialize(device:, threads: 1, interval: 5)
      @threadpool = []

      @device = device
      @threads = threads
      @interval = interval
      raise ArgumentError, "Device #{device} does not exist" unless File.exist?(device)
      raise ArgumentError, "Device #{device} is empty" unless device_size > 0
      raise ArgumentError, "Device #{device} is already mounted" if already_mounted?
    end

    def device_size
      @device_size ||= `blockdev --getsize64 #{device}`.to_i
    end

    def already_mounted?
      !`mount | grep #{device}`.empty?
    end

    def prewarm
      start_threads

      until @threadpool.all?(&:complete?)
        @threadpool.each(&:update_status)

        output_stats
        sleep interval
      end
    end

    def current_stats
      {
        bytes_completed: @threadpool.map(&:bytes_completed).inject(:+),
        total_rate: @threadpool.map(&:rate).inject(:+),
        num_up_to_date: @threadpool.select(&:up_to_date?).size,
        num_complete: @threadpool.select(&:complete?).size
      }
    end

    def output_stats
      stats = current_stats
      bytes_completed = Filesize.new(stats[:bytes_completed])
      total_rate = Filesize.new(stats[:total_rate])
      device_file_size = Filesize.new(device_size)
      time_left = ((device_file_size - bytes_completed) / total_rate)
      puts format(
        '%s / %s (%.2f%%) [%s/s] %d UpToDate - %d Complete - ETA %s',
        bytes_completed.pretty,
        device_file_size.pretty,
        100.0 * bytes_completed / device_file_size,
        total_rate.pretty,
        stats[:num_up_to_date],
        stats[:num_complete],
        total_rate > 0 ? ChronicDuration.output(time_left, format: :short) : 'Infinity'
      )
    end

  private

    def start_threads
      total_chunks = Filesize.new(device_size) / Filesize.from('1MiB')
      chunks_per_thread = (total_chunks / threads).to_i

      1.upto(threads).each do |thread_num|
        start_point = chunks_per_thread * (thread_num - 1)

        stdin, stdout, stderr, thread = Open3.popen3("dd if=#{device} of=#{device} bs=1M skip=#{start_point} seek=#{start_point} count=#{chunks_per_thread} conv=notrunc")
        stdin.close
        stdout.close

        @threadpool.push(Fireworks::DDThread.new(thread: thread, stderr: stderr))
      end
    end
  end

  class DDThread
    attr_reader :bytes_completed, :rate

    def initialize(thread:, stderr:)
      @thread = thread
      @stderr = stderr
      @eof = false
      @bytes_completed = 0
      @rate = 0
      @updated_at = nil
    end

    def complete?
      !@thread.alive? && @eof
    end

    def update_status
      usr1! # send signal to dump stderr

      sleep 0.1 # need a short sleep to let IO threads run

      buffer = attempt_read
      most_recent_status = buffer.to_s.split("\n").last
      return unless most_recent_status && (match = most_recent_status.match(/(\d+) bytes.*, (\d+(?:\.\d+)? \w+)\/s/))

      @bytes_completed = match[1].to_i
      @rate = Filesize.from(match[2]).to_i
      @updated_at = Time.now
    end

    def up_to_date?
      return false if @updated_at.nil?
      Time.now - @updated_at < 120
    end

  private

    def attempt_read
      @stderr.read_nonblock(8196)
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK
      return # No data!
    rescue EOFError
      @eof = true
    end

    def usr1!
      Process.kill('USR1', @thread.pid) if @thread.alive?
    end
  end
end
