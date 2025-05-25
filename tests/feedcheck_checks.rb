# frozen_string_literal: true

require 'faraday'
require 'nokogiri'
require 'uri'

class Status
  FAILED = true
  PASSED = false
end

def check_status_and_location(response, url, error_message)
  error = "#{error_message}Non successful status code #{response.status} when trying to access '#{url}'"

  return ["#{error}. Try using '#{response.headers['location']}' instead", Status::FAILED] if response.status.to_i.between?(300, 399) && response.headers.key?('location')
  
  return ["#{error}. Target feed is denying access. ", Status::FAILED] if response.status.to_i == 403
  
  return [error, Status::FAILED] unless response.status.to_i == 200

  ['✓ ', Status::PASSED]
end

def request_data(connection, url, error_message)
  connection.get(URI(url))
rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
  ["#{error_message}#{e.class} when trying to access '#{url}' ", Status::FAILED]
end

def parse_xml(feed, faraday)
  error_message = '✗ '
  response = request_data(faraday, feed, error_message)
  return response if response.is_a? Array

  xml_err = Nokogiri::XML(response.body).errors
  return ["#{error_message}Unusable XML syntax: #{feed} #{xml_err} ", Status::FAILED] unless xml_err.empty?

  ['✓ ', Status::PASSED]
end

def check_single_url(url, faraday)
  error_message = '✗ '
  res = request_data(faraday, url, error_message)
  return res if res.is_a? Array

  check_status_and_location(res, url, error_message)
end

def check_urls(url_arr, faraday)
  results = url_arr.map { |url| check_single_url(url, faraday) }

  [results.map(&:first).join, results.any?(&:last)]
end

def check_avatar(avatar, av_dir, faraday)
  return ['_ ', Status::PASSED] unless avatar

  return check_url(avatar, faraday) if avatar.include? '//'

  avatar_path = "#{av_dir}/#{avatar}"
  return ["✗ Avatar not found: #{avatar_path}", Status::FAILED] unless File.file?(avatar_path)

  ['✓ ', Status::PASSED]
end

def accumulate_results(result, did_fail, new_result)
  result << new_result.first

  did_fail | new_result.last
end

def check_source(key, section, faraday)
  result = [":: #{key} =>  "]
  avatar, link, feed = %w[avatar link feed].map { |k| section[k] if section.key?(k) }

  avatar_result = check_avatar(avatar, AV_DIR, faraday)
  did_fail = accumulate_results(result, Status::PASSED, avatar_result)

  url_result = check_urls([link, feed], faraday)
  did_fail = accumulate_results(result, did_fail, url_result)

  xml_result = url_result.last ? ['_ ', Status::PASSED] : parse_xml(feed, faraday)
  did_fail = accumulate_results(result, did_fail, xml_result)

  [[result.compact.join, did_fail], avatar]
end

def check_unused_files(av_dir, avatars)
  hackergotchis = Dir.foreach(av_dir).select { |f| File.file?("#{av_dir}/#{f}") }
  diff = (hackergotchis - avatars)

  return ["There are unused files in #{av_dir}: #{diff.sort.join(', ')}", Status::FAILED] unless diff.empty?

  [nil, Status::PASSED]
end
