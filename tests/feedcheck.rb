# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'iniparser'
require 'nokogiri'
require 'uri'

INI_FILE = 'planet.ini'
AV_DIR = 'hackergotchi'

def check_avatar(avatar, av_dir, faraday)
  return ['_ ', false] unless avatar

  return check_url(avatar, faraday) if avatar.include? '//'
  return ["✗\nAvatar not found: hackergotchi/#{avatar} ", true] unless File.file?("#{av_dir}/#{avatar}")

  ['✓ ', false]
end

def check_url(url, faraday)
  error_message = '✗ '

  begin
    res = faraday.get(URI(url))
  rescue Faraday::ConnectionFailed
    return ["#{error_message}Connection Failure when trying to access '#{url}' ", true]
  rescue Faraday::TimeoutError
    return ["#{error_message}Connection Timeout waiting for '#{url}' ", true]
  rescue Faraday::SSLError
    return ["#{error_message}SSL Error when trying to access '#{url}' ", true]
  end

  error = "#{error_message}Non successful status code #{res.status} when trying to access '#{url}' "
  if res.status.to_i.between?(300, 399) && res.headers.key?('location')
    return ["#{error}. Try using '#{res.headers['location']}' instead", true]
  end

  return [error, true] unless res.status.to_i == 200

  ['✓ ', false]
end

def check_urls(url_arr, faraday)
  results = url_arr.map { |url| check_url(url, faraday) }

  [results.map(&:first).join, results.any?(&:last)]
end

def parse_xml(feed, faraday)
  result = ['✗ ', true]

  begin
    xml = faraday.get(URI(feed))
  rescue Faraday::ConnectionFailed
    return ["#{result.first}Connection Failure when trying to read XML from '#{feed}' ", true]
  rescue Faraday::SSLError
    return ["#{result.first}SSL Error when trying to read XML from '#{feed}' ", true]
  end

  xml_err = Nokogiri::XML(xml.body).errors
  return ["#{result.first}Unusable XML syntax: #{feed}\n#{xml_err} ", true] unless xml_err.empty?

  ['✓ ', false]
end

def check_unused_files(av_dir, avatars)
  hackergotchis = Dir.foreach(av_dir).select { |f| File.file?("#{av_dir}/#{f}") }
  diff = (hackergotchis - avatars)

  return [nil, false] if diff.empty?

  ["There are unused files in hackergotchis: #{diff.sort.join(', ')}", true]
end

def accumulate_results(result, did_fail, new_result)
  result << new_result.first

  did_fail | new_result.last
end

def check_source(key, section, faraday)
  result = [":: #{key} =>  "]
  avatar, link, feed = %w[avatar link feed].map { |k| section[k] if section.key?(k) }

  avatar_result = check_avatar(avatar, AV_DIR, faraday)
  did_fail = accumulate_results(result, false, avatar_result)

  url_result = check_urls([link, feed], faraday)
  did_fail = accumulate_results(result, did_fail, url_result)

  xml_result = url_result.last ? ['_ ', false] : parse_xml(feed, faraday)
  did_fail = accumulate_results(result, did_fail, xml_result)

  [[result.compact.join, did_fail], avatar]
end

def write_to_file(contents, filename)
  File.open(filename, 'w') { |file| file.write contents.join }
end

def image_warning_markdown(messages)
  unused_images = messages.last.match('There are unused files in [A-Za-z]+: (.*)')[1].split(',').join("\n*")
  ["\n## Unused Images\n", "\nThere are also unused avatar files:\n\n* #{unused_images}\n"]
end

def prepare_message_markdown(message)
  header, body = message.split('=>').map(&:strip)
  return unless header && body

  ["\n### #{header.gsub(/^:: /, '')}\n", "\n#{body}\n"]
end

def create_job_summary(error_messages)
  job_summary = error_messages.map { |message| prepare_message_markdown(message) }.compact.unshift "# Feed Validity Summary\n\n## Feeds\n"
  job_summary.concat image_warning_markdown(error_messages) if error_messages.last.include? 'There are unused files in'
  File.open('error-summary.md', 'w') { |file| file.write job_summary.join }
end

planet_srcs = INI.load_file(INI_FILE)
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
      next unless section.is_a?(Hash)

      res, avatar = check_source(key, section, faraday)
      avatars << avatar
      puts res.first
      error_messages << res.first if res.last
      did_any_fail ||= res.last
    end
  end
end
workers.each(&:join)

unused_files_result = check_unused_files(AV_DIR, avatars)
if unused_files_result.last
  error_messages << unused_files_result.first
  puts "[WARNING] #{unused_files_result.first}"
end

if did_any_fail
  create_job_summary(error_messages)
  abort
end
File.delete('error-summary.md') if File.exist?('error-summary.md')
puts 'All feeds passed checks!'
