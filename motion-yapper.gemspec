# -*- encoding: utf-8 -*-
$:.unshift File.expand_path("../lib", __FILE__)
$:.unshift File.expand_path("../../lib", __FILE__)

require 'yapper/version'

Gem::Specification.new do |gem|
  gem.authors       = ["Kareem Kouddous"]
  gem.email         = ["kareemknyc@gmail.com"]
  gem.description   = "Rubymotion ORM for YapDatabase"
  gem.summary       = "Rubymotion ORM for YapDatabase"
  gem.homepage      = "https://github.com/kareemk/yapper"

  gem.files         = `git ls-files`.split($\)
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "motion-yapper"
  gem.require_paths = ["lib"]
  gem.version       = Yapper::VERSION

  gem.add_dependency 'motion-cocoapods', '~> 1.8.0'
  gem.add_dependency 'motion-logger', '~> 0.1.0'
  gem.add_development_dependency 'motion-redgreen', '~> 0.1'
end
