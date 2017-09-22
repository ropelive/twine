require "./spec_helper"

module Twine
  describe Connection do
    it "should be able to connect Redis" do
      c = Twine::Connection.new
    end

    it "should be able to update data on Redis" do
      c = Twine::Connection.new
      c.redis.set("foo", "bar")
      c.redis.get("foo").should eq("bar")
      c.redis.del("foo").should eq(1)
    end

    it "should subscribe to register channel" do
      c = Twine::Connection.new
      c.redis.subscribe "register" do |on|
        on.subscribe do |channel, subscriptions|
          channel.should eq("register")
          c.redis.unsubscribe "register"
        end
      end
    end
  end
end
