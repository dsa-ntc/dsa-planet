# frozen_string_literal: true

require 'minitest/autorun'

require_relative '../lib/feed_html_sanitizer'

# Covers unsafe and ordinary markup handled by Loofah's prune scrubber.
class FeedHtmlSanitizerTest < Minitest::Test
  def sanitize(html)
    FeedHtmlSanitizer.sanitize(html)
  end

  def test_removes_reported_twitter_script
    html = <<~HTML
      <p>Before</p>
      <script async src="//platform.twitter.com/widgets.js" charset="utf-8"></script>
      <p>After</p>
    HTML

    output = sanitize(html)

    assert_includes output, '<p>Before</p>'
    assert_includes output, '<p>After</p>'
    refute_match(/script|platform\.twitter\.com/i, output)
  end

  def test_removes_inline_and_nested_scripts
    html = <<~HTML
      <p>Hello<script>alert('xss')</script></p>
      <svg><script>alert('svg xss')</script></svg>
    HTML

    output = sanitize(html)

    assert_includes output, '<p>Hello</p>'
    assert_includes output, '<svg></svg>'
    refute_match(/script|alert/i, output)
  end

  def test_removes_embedded_content
    html = <<~HTML
      <iframe src="https://attacker.example/embed"></iframe>
      <object data="https://attacker.example/file"></object>
    HTML

    output = sanitize(html)

    refute_match(/iframe|object|attacker\.example/i, output)
  end

  def test_removes_event_handlers_and_javascript_urls
    html = <<~HTML
      <p onclick="alert(1)">Hello</p>
      <a href="java&#x73;cript:alert(1)" onmouseover="alert(2)">Link</a>
      <img src="https://example.org/photo.jpg" onerror="alert(3)">
    HTML

    output = sanitize(html)

    assert_includes output, '<p>Hello</p>'
    assert_includes output, '<a>Link</a>'
    assert_includes output, 'src="https://example.org/photo.jpg"'
    refute_match(/onclick|onmouseover|onerror|javascript:|alert/i, output)
  end

  def test_preserves_normal_article_markup
    html = <<~HTML
      <article>
        <h2>Meeting report</h2>
        <p>Workers voted <strong>yes</strong>.</p>
        <blockquote cite="https://example.org/source">Solidarity forever.</blockquote>
        <a href="https://example.org/statement">Read the statement</a>
        <img src="https://example.org/photo.jpg" alt="Picket line" width="640" height="480">
      </article>
    HTML

    output = sanitize(html)

    assert_includes output, '<h2>Meeting report</h2>'
    assert_includes output, '<strong>yes</strong>'
    assert_includes output, '<blockquote cite="https://example.org/source">'
    assert_includes output, 'href="https://example.org/statement"'
    assert_includes output, 'alt="Picket line"'
  end

  def test_recovers_malformed_feed_html
    output = sanitize('<div><p>First<p>Second<script>alert(1)')

    assert_includes output, '<p>First</p>'
    assert_includes output, '<p>Second</p>'
    refute_match(/script|alert/i, output)
  end

  def test_handles_empty_content
    assert_equal '', sanitize(nil)
  end
end
