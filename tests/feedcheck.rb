# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'iniparser'
require 'nokogiri'
require 'uri'

hash = INI.load_file('planet.ini')
av_dir = 'hackergotchi'

faraday = Faraday.new() do |f|
  f.response :follow_redirects # use Faraday::FollowRedirects::Middleware
  f.adapter Faraday.default_adapter
end

avatars = []
did_fail = false

hash.each do |key, section|
  next unless section.is_a?(Hash)

  print ":: #{key} =>  "
  feed = section['feed'] if section.key?('feed')
  avatar = section['avatar'] if section.key?('avatar')
  url_arr = []
  url_arr << section['link'] if section.key?('link')
  url_arr << feed if feed
  # Check if avatar exists
  if avatar
    if avatar.include? '//'
      url_arr << avatar
    else
      unless File.file?("#{av_dir}/#{avatar}")
        print "✗\nAvatar not found: hackergotchi/#{avatar}"
        did_fail = true
      else
        print '✓ '
      end
      avatars << avatar
    end
  end
  # Check if URLs return 200 status
  url_arr.each do |url|
    res = faraday.get(URI(url))
    error = "✗\nNon successful status code #{res.status} when trying to access `#{url}`"
    if res.status.to_i.between?(300, 399) && res.headers.key?('location')
      print "#{error}\nTry using `#{res.headers['location']}` instead"
      did_fail = true
    end
    unless res.status.to_i == 200
      print error
      did_fail = true
    else
      print '✓ '
    end
  end
  # Check is the XML actually parses as XML
  xml = faraday.get(URI(feed)).body
  xml_err = Nokogiri::XML(xml).errors
    unless xml_err.empty?
      print "✗\nUnusable XML syntax: #{feed}\n#{xml_err}"
      did_fail = true
    else
      puts '✓ '
    end
  end

avatars << 'default.png'
avatars.uniq!
hackergotchis = Dir.foreach(av_dir).select { |f| File.file?("#{av_dir}/#{f}") }
diff = (hackergotchis - avatars).sort
unless diff.empty?
  print "There are unused files in hackergotchis:\n#{diff.join(', ')}"
  did_fail = true
end

if did_fail == true
  abort
end
