# frozen_string_literal: true

require 'faraday'
require 'inifile'
require 'thread'

require_relative 'feedcheck_checks'

INI_FILE = 'planet.ini'   # ini file containing library of feeds
AV_DIR = 'hackergotchi'   # folder containing local feed avatars
WORKER_COUNT = 3          # number of concurrent workers
FEED_NAME_PADDING = 48    # number of characters before each ``=>`` in log output

faraday = Faraday.new(request: { open_timeout: 10 }) do |f|
  f.adapter :net_http
end

queue = Queue.new
known_feed_names = []
IniFile.load(INI_FILE).to_h.each do |feed_name, section|
  known_feed_names << feed_name
  queue.push([feed_name, section]) if ARGV.empty? || ARGV.include?(feed_name)
end

error_messages = []
did_any_fail = false

missing_feed_names = ARGV - known_feed_names
missing_feed_names.each do |feed_name|
  puts "#{feed_name.ljust(FEED_NAME_PADDING)} =>  not found in #{INI_FILE}"
  error_messages << "#{feed_name}\nFeed not found in #{INI_FILE}"
  did_any_fail = true
end

avatars = ['default.png']
mutex = Mutex.new

workers = Array.new(WORKER_COUNT) do
  Thread.new do
    loop do
      feed_name, section = queue.pop(true) rescue break
      next unless section.is_a?(Hash) && feed_name != 'global'

      result = check_source(feed_name, section, faraday, AV_DIR)
      puts "#{feed_name.ljust(FEED_NAME_PADDING)} =>  #{result.symbols}"

      mutex.synchronize do
        avatars << result.avatar
        error_messages << "#{feed_name}\n#{result.error_messages}" if result.failed
        did_any_fail ||= result.failed
      end
    end
  end
end
workers.each(&:join)

run_unused_check = ARGV.empty? || ARGV[0].nil?
unused_files_message = run_unused_check ? check_unused_files(AV_DIR, avatars) : nil

puts "::warning::#{unused_files_message}" if unused_files_message

if did_any_fail
  puts "::notice::#{'Feed Errors Summary'.ljust(FEED_NAME_PADDING)} =>  (avatar) (link) (feed) (xml)"
  error_messages.each { |message| puts "::error::#{message}" }

  error_messages << unused_files_message if unused_files_message

  File.open('error-summary.md', 'w') do |file|
    file.write "# Error Summary\n\n"
    error_messages.each { |message| file.write "## #{message}\n\n" }
  end

  abort
end

File.delete('error-summary.md') if File.exist?('error-summary.md')
puts '::notice::All feeds passed checks!'
