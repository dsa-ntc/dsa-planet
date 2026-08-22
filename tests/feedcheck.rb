# frozen_string_literal: true

require 'faraday'
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
avatars = ['default.png']

faraday = Faraday.new(request: { open_timeout: 10 }) do |f|
  f.adapter :net_http
end

queue = Queue.new
planet_srcs.each do |key, section|
  queue.push([key, section]) if ARGV.empty? || ARGV.include?(key)
end

workers = (0...3).map do
  Thread.new do
    until queue.empty?
      key, section = queue.pop
      next unless section.is_a?(Hash) && (key != 'global')

      res, avatar = check_source(key, section, faraday)
      avatars << avatar

      puts ":: #{res[:key]} => #{res[:details]}"

      error_messages << res if res[:did_fail]
      did_any_fail ||= res[:did_fail]
    end
  end
end
workers.each(&:join)

unused_files_result = check_unused_files(AV_DIR, avatars) if ARGV.empty? || ARGV[0].nil? || !ARGV[0]

if unused_files_result && unused_files_result.last == Status::FAILED
  unused_data = unused_files_result.first
  puts "::warning::There are unused files in #{unused_data[:dir]}: #{unused_data[:files].join(', ')}"
  error_messages << unused_data
end

if did_any_fail
  puts 'Feed Errors Summary => (avatar) (link) (feed) (xml)'
  error_messages.each do |message|
    next if message[:type] == :unused_files

    puts "::error:: #{message[:key]} => #{message[:details]}"
  end

File.delete('error-summary.md') if File.exist?('error-summary.md')
puts '::notice::All feeds passed checks!'
