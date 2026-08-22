# frozen_string_literal: true

require 'faraday'
require 'rss'
require 'uri'

module Status
  FAILED  = :failed
  SKIPPED = :skipped
  PASSED  = :passed

  PREFIX = {
    PASSED  => '✓ ',
    FAILED  => '✗ ',
    SKIPPED => '~ '
  }.freeze
end

def check_status_and_location(response, url, error_message)
  status = response.status.to_i
  location = response.headers['location']
  base_error = "#{error_message}(status code #{status}) "

  if status.between?(300, 399) && location
    uri = URI.parse(location) rescue nil
    if uri&.host&.end_with?('google.com') && uri&.path == '/sorry/index'
      return ["#{base_error}(google bot challenge) ", Status::SKIPPED]
    end
    return ["#{base_error}(redirect to '#{location}') ", Status::FAILED]
  end

  return ["#{base_error}(access denied) ", Status::FAILED] if status == 403

  return ["#{base_error}", Status::FAILED] unless status == 200

  ['✓ ', Status::PASSED]
end

def request_data(connection, url, error_message)
  connection.get(URI(url))
rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
  ["#{error_message}#{e.class} when trying to access '#{url}' ", Status::FAILED]
end

def parse_feed(feed, faraday)
  error_message = '✗ '
  response = request_data(faraday, feed, error_message)
  return response if response.is_a? Array

  begin
    parsed_feed = RSS::Parser.parse(response.body, false)

    unless parsed_feed
      return ["#{error_message}Unparseable feed format", Status::FAILED]
    end

  rescue RSS::Error => e
    return ["#{error_message}Unusable Feed syntax: #{feed} (#{e.message})", Status::FAILED]
  end

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

  has_failures = results.any? { |res| res.last == Status::FAILED }
  status_symbol = has_failures ? Status::FAILED : Status::PASSED

  [results.map(&:first).join, status_symbol]
end

def check_avatar(avatar, av_dir, faraday)
  return ['~ ', Status::SKIPPED] unless avatar

  return check_urls([avatar], faraday) if avatar.include? '//'

  avatar_path = "#{av_dir}/#{avatar}"
  return ["✗ Avatar not found: #{avatar_path} ", Status::FAILED] unless File.file?(avatar_path)

  ['✓ ', Status::PASSED]
end

def accumulate_results(result, did_fail, new_result)
  result << new_result.first

  did_fail | new_result.last
end

def check_source(key, section, faraday)
  avatar, link, feed = %w[avatar link feed].map { |k| section[k] if section.key?(k) }

  avatar_msg, avatar_status = check_avatar(avatar, AV_DIR, faraday)
  link_msg, link_status     = check_urls([link, feed], faraday)

  feed_msg, feed_status     = link_status == Status::FAILED ? ['~ ', Status::SKIPPED] : parse_feed(feed, faraday)

  did_fail = [avatar_status, link_status, feed_status].include?(Status::FAILED)

  result = {
    key: key,
    did_fail: did_fail,
    details: [avatar_msg, link_msg, feed_msg].join
  }

  [result, avatar]
end

def check_unused_files(av_dir, avatars)
  hackergotchis = Dir.foreach(av_dir).select { |f| File.file?("#{av_dir}/#{f}") }
  diff = (hackergotchis - avatars)

  return [{ type: :unused_files, dir: av_dir, files: diff.sort }, Status::FAILED] unless diff.empty?

  [nil, Status::PASSED]
end
