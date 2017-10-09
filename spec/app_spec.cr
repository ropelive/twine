require "./spec_helper"

module Twine
  PREFIX = "twine-test-"
  SECRET = SecureRandom.uuid

  app = Twine::App.new prefix: PREFIX, secret: SECRET
  headers = HTTP::Headers{"Bearer" => SECRET}

  describe App do
    it "should be able to start web server on default port" do
      app.listen block: false

      response = HTTP::Client.get app.url
      response.body.should eq(Twine::App::WELCOME)
      response.status_code.should eq(200)

      app.close
    end

    it "should support prefixing" do
      app.key_for.any.should eq("#{PREFIX}*")
      app.key_for.server("foo")
                 .should eq("#{PREFIX}#{Twine::App::SERVER_PREFIX}foo")
    end

    it "should support custom secret" do
      app.check_secret(SECRET).should be_true
    end

    describe "get_all" do
      it "should return all related data from Redis" do
        err, keys = app.get_all
        err.should be_nil
      end
    end

    describe "delete_all" do
      it "should delete all related data from Redis" do
        err = app.delete_all
        err.should be_nil

        err, keys = app.get_all
        err.should be_nil
        keys.as(Array).size.should eq(0)
      end
    end

    {% for name in %w(server node) %}

      describe "{{ name.id }}s" do
        kite_id = nil
        new_kite_id = nil

        describe "POST /{{ name.id }}s" do
          it "POST should handle malformed data" do
            app.listen block: false

            response = HTTP::Client.post \
              "#{app.url}/{{ name.id }}s",
                body: "broken data",
                headers: headers

            response.status_code.should eq(400)

            result = JSON.parse response.body
            result["kite_id"]?.should be_nil
            result["error"].should eq(Twine::Error::DATA)

            app.close
          end

          it "POST should create a new {{ name.id }} with valid data" do
            app.listen block: false

            response = HTTP::Client.post \
              "#{app.url}/{{ name.id }}s",
                body: %({"version": "1.0"}),
                headers: headers

            response.status_code.should eq(201)

            result = JSON.parse response.body
            result["kite_id"]?.should_not be_nil
            kite_id = result["kite_id"]

            app.close
          end

          it "POST should fail with wrong token" do
            app.listen block: false

            response = HTTP::Client.post \
              "#{app.url}/{{ name.id }}s",
                body: %({"version": "1.0"}),
                headers: HTTP::Headers{"Bearer" => "so secret"}

            response.status_code.should eq(401)

            result = JSON.parse response.body
            result["kite_id"]?.should be_nil
            result["error"].should eq(Twine::Error::UNAUTHORIZED)

            app.close
          end

        end

        describe "GET /{{ name.id }}s/:id?" do
          it "GET should return available {{ name.id }}s" do
            app.listen block: false

            response = HTTP::Client.get \
              "#{app.url}/{{ name.id }}s",
              headers: headers

            response.status_code.should eq(200)

            result = JSON.parse response.body
            result.size.should eq(1)
            result[0].should eq(kite_id)

            # create new server
            response = HTTP::Client.post \
              "#{app.url}/{{ name.id }}s",
                body: %({"version": "1.0"}),
                headers: headers

            response.status_code.should eq(201)

            result = JSON.parse response.body
            result["kite_id"]?.should_not be_nil
            new_kite_id = result["kite_id"]

            # re-fetch {{ name.id }}s
            response = HTTP::Client.get \
              "#{app.url}/{{ name.id }}s",
              headers: headers

            response.status_code.should eq(200)

            result = JSON.parse response.body
            result.size.should eq(2)

            result.includes?(kite_id).should be_true
            result.includes?(new_kite_id).should be_true

            app.close
          end

          it "GET should return {{ name.id }} data with status code 200" do
            app.listen block: false

            response = HTTP::Client.get \
              "#{app.url}/{{ name.id }}s/#{kite_id}",
              headers: headers

            response.status_code.should eq(200)

            result = JSON.parse response.body
            result[kite_id.to_s]?.should_not be_nil
            result[kite_id.to_s]["version"].should eq("1.0")

            {% if name.id == "server" %}
            result[kite_id.to_s]["connections"].should eq("0")
            {% end %}

            app.close
          end

          it "GET should return 404 if given {{ name.id }} not found" do
            app.listen block: false

            response = HTTP::Client.get \
              "#{app.url}/{{ name.id }}s/foobarbaz",
              headers: headers

            response.status_code.should eq(404)

            app.close
          end

          it "GET should fail with wrong token" do
            app.listen block: false

            response = HTTP::Client.get \
              "#{app.url}/{{ name.id }}s",
              headers: HTTP::Headers{"Bearer" => "so secret"}

            response.status_code.should eq(401)

            result = JSON.parse response.body
            result["error"].should eq(Twine::Error::UNAUTHORIZED)

            app.close
          end

        end

        describe "DELETE /{{ name.id }}s/:id" do
          it "DELETE should delete the given {{ name.id }} if exists" do
            app.listen block: false

            response = HTTP::Client.delete \
              "#{app.url}/{{ name.id }}s/#{kite_id}",
              headers: headers

            response.status_code.should eq(200)

            result = JSON.parse response.body
            result["ok"].should be_true

            response = HTTP::Client.get \
              "#{app.url}/{{ name.id }}s/#{kite_id}",
              headers: headers

            response.status_code.should eq(404)

            app.close
          end

          it "DELETE should fail with wrong token" do
            app.listen block: false

            response = HTTP::Client.delete \
              "#{app.url}/{{ name.id }}s/#{kite_id}",
              headers: HTTP::Headers{"Bearer" => "so secret"}

            response.status_code.should eq(401)

            result = JSON.parse response.body
            result["error"].should eq(Twine::Error::UNAUTHORIZED)

            app.close
          end

        end

        describe "PATCH /{{ name.id }}s/:id" do
          it "PATCH should update data for given {{ name.id }} if exists" do
            app.listen block: false

            # try to patch a non-existent kite
            response = HTTP::Client.patch \
              "#{app.url}/{{ name.id }}s/#{kite_id}",
              headers: headers

            response.status_code.should eq(404)

            response = HTTP::Client.patch \
              "#{app.url}/{{ name.id }}s/#{new_kite_id}",
              body: %({"version": "2.0", "connections": "2"}),
              headers: headers
            response.status_code.should eq(200)

            result = JSON.parse response.body
            result["ok"].should be_true

            response = HTTP::Client.get \
              "#{app.url}/{{ name.id }}s/#{new_kite_id}",
              headers: headers

            response.status_code.should eq(200)

            result = JSON.parse response.body
            result[new_kite_id.to_s]?.should_not be_nil

            result[new_kite_id.to_s]["version"].should eq("2.0")
            result[new_kite_id.to_s]["connections"].should eq("2")

            app.close
          end

          it "PATCH should fail with wrong token" do
            app.listen block: false

            response = HTTP::Client.patch \
              "#{app.url}/{{ name.id }}s/#{new_kite_id}",
              body: %({"version": "2.0"}),
              headers: HTTP::Headers{"Bearer" => "so secret"}

            response.status_code.should eq(401)

            result = JSON.parse response.body
            result["error"].should eq(Twine::Error::UNAUTHORIZED)

            app.close
          end

        end
      end
    {% end %}

    describe "GET /connect" do
      app.delete_all

      it "should error when there is no server available " do
        app.listen block: false

        response = HTTP::Client.get(
          "#{app.url}/connect",
        )

        response.status_code.should eq(400)
        app.close
      end

      it "should redirect requests to first available server" do
        app.listen block: false

        # Create four servers
        servers = [] of String

        4.times do
          response = HTTP::Client.post(
            "#{app.url}/servers",
            body: %({"version": "1.0", "connections": 3}),
            headers: headers
          )
          response.status_code.should eq(201)
          result = JSON.parse response.body
          result["kite_id"]?.should_not be_nil
          servers << result["kite_id"].to_s
        end

        servers.size.should eq(4)
        busy_servers = servers.sample(3)
        busy_servers.each do |server|
          servers.delete server
          response = HTTP::Client.patch(
            "#{app.url}/servers/#{server}",
            body: %({"connections": 5}),
            headers: headers
          )
          response.status_code.should eq(200)
          result = JSON.parse response.body
          result["ok"]?.should be_true
        end

        expected_server = servers[0]

        response = HTTP::Client.get(
          "#{app.url}/connect",
          headers: headers
        )

        response.status_code.should eq(302)

        new_location = response.headers["Location"]
        new_location.should eq("#{app.url}/connect/#{expected_server}")

        response = HTTP::Client.patch \
          "#{app.url}/servers/#{expected_server}",
            body: %({"url": "https://google.com"}),
            headers: headers
        response.status_code.should eq(200)

        result = JSON.parse response.body
        result["ok"].should be_true

        response = HTTP::Client.get(
          "#{app.url}/connect",
        )

        response.status_code.should eq(302)

        new_location = response.headers["Location"]
        new_location.should eq("https://google.com")

        app.close
      end
    end
  end

  app.delete_all
end
