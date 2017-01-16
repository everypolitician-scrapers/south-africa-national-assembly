#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def email_from(nodes)
  return if nodes.nil? || nodes.empty?
  nodes.first.text.sub('mailto:', '')
end

@prefixes = %w(Adv Dr Mrs Mr Ms Professor Rev Prince).to_set
def remove_prefixes(name)
  enum = name.split(/\s/).slice_before { |w| !@prefixes.include? w.chomp('.') }
  [enum.take(1), enum.drop(1)].map { |l| l.join ' ' }
end

def scrape_list(url)
  noko = noko_for(url)
  noko.css('.list-of-people a[href*="/person/"]/@href').each do |p|
    scrape_person(URI.join(url, p.text))
  end
  next_page = noko.css('.pagination a.next/@href').text
  scrape_list(URI.join(url, next_page)) unless next_page.empty?
end

def scrape_person(url)
  noko = noko_for(url)
  sidebar = noko.css('div.constituency-party')

  party_node = sidebar.at_xpath('.//h3[text()="Party"]/following-sibling::ul/li')
  party_info = party_node ? party_node.text.strip : 'Independent (IND)'
  party, party_id = party_info.match(/(.*) \((.*)\)/).captures rescue [party_info, '']

  prefix, name = remove_prefixes(noko.css('div.title-space h1').text.gsub(/[[:space:]]+/, ' ').tidy)

  data = {
    id:               url.to_s[/person\/(.*)\//, 1],
    name:             name,
    honorific_prefix: prefix,
    party:            party,
    party_id:         party_id,
    area:             sidebar.xpath('.//h3[.="Province"]/following-sibling::ul[1]/li').text.strip,
    email:            email_from(noko.css('div.contact-actions__email a[href*="mailto:"]/@href')),
    term:             '26',
    image:            noko.css('.profile-pic img/@src').text,
    source:           url.to_s,
  }
  data[:image] = URI.join(url, data[:image]).to_s unless data[:image].to_s.empty?
  data[:area] = 'National' if data[:area].to_s.empty?
  ScraperWiki.save_sqlite(%i(id term), data)
end

scrape_list('http://www.pa.org.za/organisation/national-assembly/people/')
