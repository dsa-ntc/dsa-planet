# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'iniparser'
require 'nokogiri'
require 'thread'
require 'uri'

INI_FILE = 'planet.ini'
AV_DIR = 'hackergotchi'

def initialize_faraday
  Faraday.new(request: {open_timeout: 5}) do |f|
    f.response :follow_redirects
    f.adapter :net_http
  end
end

def check_avatar(avatar, av_dir, faraday)
  result = ["_ ", false]

  if avatar
    if avatar.include? '//'
      result = check_url(avatar, faraday)
    else
      unless File.file?("#{av_dir}/#{avatar}")
        result = ["✗\nAvatar not found: hackergotchi/#{avatar} ", true]
      else
        result = ['✓ ', false]
      end
    end
  end
  result
end

def check_url(url, faraday)
  error_message = "✗ "

  begin
    res = faraday.get(URI(url))
  rescue Faraday::ConnectionFailed
    return ["#{error_message}Connection Failure when trying to access '#{url}' ", true]
  rescue Faraday::SSLError
    return ["#{error_message}SSL Error when trying to access '#{url}' ", true]
  end

  error = "#{error_message}Non successful status code #{res.status} when trying to access '#{url}' "
  return ["#{error}\nTry using '#{res.headers['location']}' instead", true] if res.status.to_i.between?(300, 399) && res.headers.key?('location')

  return [error, true] unless res.status.to_i == 200

  ['✓ ', false]
end

def check_urls(url_arr, faraday)
  results = url_arr.map { |url| check_url(url, faraday) }
  [results.map(&:first).join, results.any? { |r| r.last }]
end

def parse_xml(feed, faraday)
  result = ["✗ ", true]

  begin
    xml = faraday.get(URI(feed))
  rescue Faraday::ConnectionFailed
    return ["#{result.first}Connection Failure when trying to read XML from '#{feed}' ", true]
  rescue Faraday::SSLError
    return ["#{result.first}SSL Error when trying to read XML from '#{feed}' ", true]
  else
    xml_err = Nokogiri::XML(xml.body).errors
    unless xml_err.empty?
      return ["#{result.first}Unusable XML syntax: #{feed}\n#{xml_err} ", true]
    end
    ['✓ ', false]
  end
end

def check_unused_files(av_dir, avatars)
  hackergotchis = Dir.foreach(av_dir).select { |f| File.file?("#{av_dir}/#{f}") }
  diff = (hackergotchis - avatars)

  if diff.empty?
    [nil, false]
  else
    ["There are unused files in hackergotchis:\n#{diff.join(', ')}", true]
  end
end

def check_source(key, section, faraday)
  did_fail = false
  result = []
  avatar = section['avatar'] if section.key?('avatar')

  result << ":: #{key} =>  "
  avatar_result = check_avatar(avatar, AV_DIR, faraday)
  result << avatar_result.first
  did_fail |= avatar_result.last

  link = section['link'] if section.key?('link')
  feed = section['feed'] if section.key?('feed')
  url_result = check_urls([link, feed], faraday)
  result << url_result.first
  did_fail |= url_result.last

  unless url_result.last
    xml_result = parse_xml(feed, faraday)
    result << xml_result.first
    did_fail |= xml_result.last
  end

  return [result.compact.join, did_fail], avatar
end

def create_job_summary(error_messages)
  job_summary = ["# Feed sources with errors\n"]
  error_messages.each do |error_message|
    error_message_parts = error_message.split('=>')

    header = error_message_parts[0]&.strip.sub(/^:: /, '')
    body = error_message_parts[1]&.strip

    if header && body
      job_summary << "\n## #{header}\n"
      job_summary << "\n#{body}\n"
    end
  end
  job_summary_text = job_summary.reduce(:+)

  if ENV['CI']
    ENV['GITHUB_STEP_SUMMARY'] = job_summary_text
    puts ENV['GITHUB_STEP_SUMMARY']
  else
    File.open("error-summary.md", "w") do |file|
      file.write job_summary_text
    end
  end
end

def main
  faraday = initialize_faraday()
  planet_srcs = INI.load_file(INI_FILE)

  did_any_fail = false
  error_messages = []
  avatars = []

  queue = Queue.new
  planet_srcs.each do |key, section|
    queue.push([key, section])
  end
  workers = (0...3).map do
    Thread.new do
      until queue.empty?
        key, section = queue.pop
        next unless section.is_a?(Hash)

        res, avatar = check_source(key, section, faraday)
        avatars << avatar
        puts res.first if res.first
        error_messages << res.first if res.last
        did_any_fail ||= res.last
      end
    end
  end
  workers.each(&:join)

  unused_files_result = check_unused_files(AV_DIR, avatars)
  error_messages << unused_files_result.first if unused_files_result.last
  did_any_fail ||= unused_files_result.last

  if did_any_fail
    create_job_summary(error_messages)
  end
end

main()
