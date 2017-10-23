require "redis"

module Twine
  class Connection
    property redis : Redis

    def initialize
      url = ENV["REDIS_URL"].to_s
      puts "redis url before #{@url}!"
      ENV["REDIS_URL"] ||= "redis://localhost:6379"
      url = ENV["REDIS_URL"].to_s
      puts "redis url before #{@url}!"
      
      @redis = Redis.new url: url
      at_exit do
        @redis.close
      end
    end
  end
end
