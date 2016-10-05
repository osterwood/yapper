require "bundler/gem_tasks"
$:.unshift("/Library/RubyMotion/lib")
require 'motion/project/template/ios'
require 'motion-cocoapods'
require 'motion-logger'
require 'motion-redgreen'
require 'bubble-wrap/core'
require 'yapper'

Motion::Project::App.setup do |app|
  app.name = 'Yapper'
  app.redgreen_style = :full
  
  app.pods do
     pod 'NSData+MD5Digest'
  end
end

desc "Build the gem"
task :gem do
  sh "bundle exec gem build nanoid.gemspec"
  sh "mkdir -p pkg"
  sh "mv *.gem pkg/"
end
