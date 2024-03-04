# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'inifile'

require_relative 'feedcheck_checks'
require_relative 'feedcheck_job_summary'

INI_FILE = 'planet.ini'
AV_DIR = 'hackergotchi'

def write_to_file(contents, filename)
  File.open(filename, 'w') { |file| file.write contents.join }
end

planet_srcs = IniFile.load(INI_FILE).to_h
did_any_fail = false
error_messages = []
avatars = ['default.webp']

faraday = Faraday.new(request: { open_timeout: 10 }) do |f|
  f.response :follow_redirects
  f.adapter :net_http
end

queue = Queue.new
planet_srcs.each do |key, section|
  queue.push([key, section]) if ARGV.empty? || ARGV.include?(key)
end

workers = (0...8).map do
  Thread.new do
    until queue.empty?
      key, section = queue.pop
      next unless section.is_a?(Hash) && (key != 'global')

      res, avatar = check_source(key, section, faraday)
      avatars << avatar
      puts res.first
      error_messages << res.first if res.last
      did_any_fail ||= res.last
    end
  end
end
workers.each(&:join)

unused_files_result = check_unused_files(AV_DIR, avatars) if ARGV.empty? || ARGV[0].nil? || !ARGV[0]
puts "::warning::#{unused_files_result.first}" unless unused_files_result.nil? || !unused_files_result.last

if did_any_fail
  puts 'Feed Errors Summary'
  error_messages.each do |message|
    puts "::error::#{message}"
  end
  create_job_summary(error_messages)
  abort
end
File.delete('error-summary.md') if File.exist?('error-summary.md')
puts '::notice::All feeds passed checks!'
