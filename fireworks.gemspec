Gem::Specification.new do |s|
  s.name        = 'fireworks'
  s.version     = '0.0.1'
  s.date        = '2015-08-06'
  s.summary     = 'Faster EBS prewarming'
  s.description = 'Faster EBS prewarming via running multiple dds in parallel'
  s.authors     = ['Andrew Grim']
  s.email       = 'stopdropandrew@gmail.com'
  s.files       = `git ls-files -z`.split("\x0")
  s.executables = ['fireworks']
  s.homepage    = 'https://github.com/kongregate/fireworks'
  s.license     = 'MIT'

  s.add_runtime_dependency 'filesize'
  s.add_runtime_dependency 'chronic_duration'
end
