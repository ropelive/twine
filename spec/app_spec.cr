require "./spec_helper"

module Twine
  describe App do
    it "should be able to start web server on default port" do
      app = Twine::App.new
      app.listen block = false

      response = HTTP::Client.get app.url
      response.body.should eq(Twine::App::WELCOME)
      response.status_code.should eq(200)
    end
  end
end
