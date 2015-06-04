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

require "./lycoris"

def test_twitterClient
  keys = YAML.load_file("config.yml")

  clients = keys[:twitter2].map  { |key| TwitterClient.new(*key.values) }
                          .each { |client| p client.get("statuses/user_timeline", count: 200) }
end

def test_lycoris
  keys = YAML.load_file("config.yml")

  clients = keys[:twitter2].map  { |key| Lycoris.new(*key.values, keys) }
  Thread.new { clients[0].process(clients[1]) }
  Thread.new { clients[0].wait }

  Thread.abort_on_exception = true
  sleep
end

def test
  #test_twitterClient
  test_lycoris
end

test if __FILE__ == $0
