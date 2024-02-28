# frozen_string_literal: true

task default: %w[build]

desc 'update latest articles from feeds and build the jekyll planet'
task :build do
  system 'pluto update planet.ini'
  ruby 'bin/jekyll_planet.rb'
end
