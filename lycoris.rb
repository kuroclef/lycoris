#!/usr/bin/ruby
# coding: utf-8
=begin
/**
 *  Lycoris -- A Twitter bot using Markov chains.
 *  Copyright (C) 2015  Kazumi Moriya <kuroclef@gmail.com>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
=end

require "bundler/setup"
require "json"
require "oauth"
require "open-uri"
require "rexml/document"
require "yaml"

class TwitterClient
  def initialize consumer_key, consumer_secret, access_token, access_token_secret
    @@consumer ||= OAuth::Consumer.new(consumer_key, consumer_secret, site: "https://api.twitter.com")
    @client      = OAuth::AccessToken.new(@@consumer, access_token, access_token_secret)
  end

  def api method
    "https://api.twitter.com/1.1/#{method}.json?"
  end

  def get method, params = {}
    JSON.parse(@client.get("#{api(method)}#{URI.encode_www_form(params)}").body, symbolize_names: true)
  end

  def post method, params = {}
    @client.post("#{api(method)}", params)
  end

  def get_stream params = {}
    while true
      uri = URI.parse("https://userstream.twitter.com/1.1/user.json?#{URI.encode_www_form(params)}")

      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      https.start

      request = Net::HTTP::Get.new(uri.request_uri, "Accept-Encoding": "identity")
      request.oauth!(https, @@consumer, @client)

      https.request(request) { |response|
        buffer = ""
        response.read_body { |chunk|
          buffer << chunk
          while line = buffer[/.*(\r\n)+/m]
            buffer.slice!(line)
            yield JSON.parse(line, symbolize_names: true) rescue nil
          end
          sleep 0.1
        }
      }
      https.finish
    end
  end
end

class TwitterObject
  def initialize from_object
    @object = from_object
  end

  def [] key
    @object[key]
  end

  def is_tweet
    @object.has_key?(:text)
  end

  def is_protected
    @object[:user][:protected]
  end

  def is_reply_to screen_name
    @object[:in_reply_to_screen_name] == screen_name
  end

  def is_tweeted_by screen_name
    @object[:user][:screen_name] == screen_name
  end

  def is_valid
    @object[:text] !~ /@|#|RT|ttp|\n|[‘’“”〈〉《》「」『』【】〔〕（）：；＜＞［］｛｝｢｣]/
  end
end

class Lycoris
  def initialize consumer_key, consumer_secret, access_token, access_token_secret, keys
    @client = TwitterClient.new(consumer_key, consumer_secret, access_token, access_token_secret)
    @me     = @client.get("account/verify_credentials")[:screen_name]
    @memory = []
    @keys   = keys
  end

  def wait
    while true
      if Time.now.to_i % 3600 != 0
        sleep 1
        next
      end
      tweet
      sleep 3000
    end
  end

  def tweet
    @client.post("statuses/update", status: remind)
  end

  def get_stream params = {}, &proc
    @client.get_stream(params, &proc)
  end

  def post_tweet params = {}
    @client.post("statuses/update", params)
  end

  def process client_to_get = self, client_to_post = self
    client_to_get.get_stream(track: @me) { |object|
      object = TwitterObject.new(object)
      next if !object.is_tweet

      if object.is_reply_to(@me)
        client_to_post.post_tweet(status: "@#{object[:user][:screen_name]} #{remind}", in_reply_to_status_id: object[:id])
        next
      end

      next if  object.is_protected
      next if  object.is_tweeted_by(@me)
      next if !object.is_valid

      object[:text].split(/[、。]/).each { |text|
        next if text.empty?
        store(parse(trim(text)))
      }
    }
  end

  def trim text
    text.gsub(/@\w+/, "").gsub(/[[:blank:]]+/, " ").strip
  end

  def parse text
    params   = { appid: @keys[:yahoo], sentence: text, results: "ma", response: "surface,pos" }
    response = open("https://jlp.yahooapis.jp/MAService/V1/parse?#{URI.encode_www_form(params)}")
    return [] if response.status[0] != "200"

    result   = []
    elements = REXML::Document.new(response).elements["/ResultSet/ma_result/word_list"]

    elements.each_element { |element|
      hash = {}
      element.each_element { |e| hash[e.name.to_sym] = e.text }
      result << hash
    }
    return result
  end

  def store word_list
    return if word_list.empty?

    words = [ "__TAG__" ]
    parts = [ "__TAG__" ]
    word_list.each { |word| push(word, words, parts) }

    words.each { |word|
      return if word =~ /^[ "'():;<>\[\]{}]$/
      return if word.length > 10
    }

    @memory.push(*words)
  end

  def push word, words, parts
    if parts[-1] == word[:pos]
      words[-1] << word[:surface]
      return
    end

    if parts[-1] == "接頭辞"
      words[-1] << word[:surface]
      parts[-1] =  word[:pos]
      return
    end

    if word[:pos] == "接尾辞" && parts[-1] != "__TAG__"
      words[-1] << word[:surface]
      return
    end

    if word[:pos] == "助詞" && parts[-1].include?("動詞")
      words[-1] << word[:surface]
      return
    end

    words << word[:surface]
    parts << word[:pos]
  end

  def remind
    text = ""
    a    = "__TAG__"
    while true
      record = lookup(a)
      raise "lookup error." if record.nil?
      a = record[1]
      break if a == "__TAG__"
      text << a
    end
    text << "。" if text[-1] =~ /[\p{Hiragana}\p{Katakana}]/
    return remind if text.length > 120
    return text
  end

  def lookup a
    table  = []
    @memory.each_cons(2) { |row|
      table << row if row[0] == a
    }
    return table.sample
  end
end

def main
  keys = YAML.load_file("config.yml")

  clients = keys[:twitter].map  { |key| Lycoris.new(*key.values, keys) }
  Thread.new { clients[0].process(clients[1]) }
  Thread.new { clients[0].wait }

  Thread.abort_on_exception = true
  sleep
end

main if __FILE__ == $0
