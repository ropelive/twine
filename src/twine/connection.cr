require "redis"

module Twine
  class Connection
    property redis : Redis

    def initialize
      @redis = Redis.new
      at_exit do
        @redis.close
      end
    end
  end
end
