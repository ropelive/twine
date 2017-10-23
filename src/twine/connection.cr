require "redis"

module Twine
  class Connection
    property redis : Redis

    def initialize
      ENV["REDIS_URL"] ||= "redis://localhost:6379"
      url = ENV["REDIS_URL"].to_s

      @redis = Redis.new url: url
      at_exit do
        @redis.close
      end
    end
  end
end
