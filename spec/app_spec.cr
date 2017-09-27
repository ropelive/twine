require "./spec_helper"

module Twine
  PREFIX = "twine-test-"
  app = Twine::App.new prefix: PREFIX

  describe App do
    it "should be able to start web server on default port" do
      app.listen block: false

      response = HTTP::Client.get app.url
      response.body.should eq(Twine::App::WELCOME)
      response.status_code.should eq(200)

      app.close
    end

    it "should support prefixing" do
      app.get_key.any.should eq("#{PREFIX}*")
      app.get_key.server("foo")
                 .should eq("#{PREFIX}#{Twine::App::SERVER_PREFIX}foo")
    end

    describe "get_all" do
      it "should return all related data from Redis" do
        err, keys = app.get_all
        err.should be_nil
      end
    end

    it "should cleanup test data" do
      err = app.delete_all
      err.should be_nil

      err, keys = app.get_all
      err.should be_nil
      keys.as(Array).size.should eq(0)
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
                body: "broken data"
            response.status_code.should eq(400)

            result = JSON.parse_raw(response.body).as(Hash)
            result.has_key?("kite_id").should be_false
            result["error"].should eq(Twine::Error::DATA)

            app.close
          end

          it "POST should create a new {{ name.id }} with valid data" do
            app.listen block: false

            response = HTTP::Client.post \
              "#{app.url}/{{ name.id }}s",
                body: %({"{{ name.id }}": "foo"})
            response.status_code.should eq(201)

            result = JSON.parse_raw(response.body).as(Hash)
            result.has_key?("kite_id").should be_true
            kite_id = result["kite_id"]

            app.close
          end
        end

        describe "GET /{{ name.id }}s/:id?" do
          it "GET should return available {{ name.id }}s" do
            app.listen block: false

            response = HTTP::Client.get "#{app.url}/{{ name.id }}s"
            response.status_code.should eq(200)

            result = JSON.parse_raw(response.body).as(Array)
            result.size.should eq(1)
            result[0].should eq(app.get_key.{{ name.id }}(kite_id))

            # create new server
            response = HTTP::Client.post \
              "#{app.url}/{{ name.id }}s",
                body: %({"{{ name.id }}": "foo"})
            response.status_code.should eq(201)

            result = JSON.parse_raw(response.body).as(Hash)
            result.has_key?("kite_id").should be_true
            new_kite_id = result["kite_id"]

            # re-fetch {{ name.id }}s
            response = HTTP::Client.get "#{app.url}/{{ name.id }}s"
            response.status_code.should eq(200)

            result = JSON.parse_raw(response.body).as(Array)
            result.size.should eq(2)
            result.includes?(app.get_key.{{ name.id }}(kite_id)).should be_true
            result.includes?(app.get_key.{{ name.id }}(new_kite_id)).should be_true

            app.close
          end

          it "GET should return given {{ name.id }} data with status code 200" do
            app.listen block: false

            response = HTTP::Client.get "#{app.url}/{{ name.id }}s/#{kite_id}"
            response.status_code.should eq(200)

            result = JSON.parse_raw(response.body).as(Hash)
            result.has_key?("version").should be_true
            result["version"].should eq("1.0")

            app.close
          end

          it "GET should return 404 if given {{ name.id }} not found" do
            app.listen block: false

            response = HTTP::Client.get "#{app.url}/{{ name.id }}s/foobarbaz"
            response.status_code.should eq(404)

            app.close
          end
        end

        describe "DELETE /{{ name.id }}s/:id" do
          it "DELETE should delete the given {{ name.id }} if exists" do
            app.listen block: false

            response = HTTP::Client.delete "#{app.url}/{{ name.id }}s/#{kite_id}"
            response.status_code.should eq(200)

            result = JSON.parse_raw(response.body).as(Hash)
            result["ok"].should be_true

            response = HTTP::Client.get "#{app.url}/{{ name.id }}s/#{kite_id}"
            response.status_code.should eq(404)

            app.close
          end
        end

        describe "PATCH /{{ name.id }}s/:id" do
          it "PATCH should update data for the given {{ name.id }} if exists" do
            app.listen block: false

            # try to patch a non-existent kite
            response = HTTP::Client.patch "#{app.url}/{{ name.id }}s/#{kite_id}"
            response.status_code.should eq(404)

            response = HTTP::Client.patch \
              "#{app.url}/{{ name.id }}s/#{new_kite_id}",
                body: %({"version": "2.0"})
            response.status_code.should eq(200)

            result = JSON.parse_raw(response.body).as(Hash)
            result["ok"].should be_true

            response = HTTP::Client.get "#{app.url}/{{ name.id }}s/#{new_kite_id}"
            response.status_code.should eq(200)

            result = JSON.parse_raw(response.body).as(Hash)
            result["version"].should eq("2.0")

            app.close
          end
        end
      end
    {% end %}
  end

  app.delete_all
end
