require "./spec_helper"

include MvamBot::Spec
include MvamBot::Spec::Wit

describe ::MvamBot::Bot do

  describe "surveys" do

    it "should start survey on a start action" do
      MvamBot::Spec::DB.cleanup
      user = Factory::DB.user_with_location

      messages = handle_message("/start", user: user, understand: response({ "intent" => "Salutation" }))

      messages.size.should eq(1)
      messages[0][:text].should contain("I would like to ask you a few questions if you have a minute")

      user.conversation_step.not_nil!.should contain("survey/start")
    end

    it "should not greet the user again when returning from a clarification to the initial step" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new
      user = Factory::DB.user_with_location

      handle_message("/start", user: user, bot: bot, understand: response({ "intent" => "Salutation" }))
      handle_message("Why?", user: user, bot: bot, understand: response({"intent" => "AskWhy"}))
      handle_message("Fine", user: user, bot: bot, understand: response({"yes_no" => "Yes"}))

      messages = bot.messages
      messages.size.should eq(3)
      messages[0][:text].should contain("Hello!")
      messages[2][:text].should_not contain("Hello!")

      user.conversation_step.not_nil!.should contain("survey/start")
    end

    it "should not save a survey response if the user refused the survey" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new
      user = Factory::DB.user_with_location

      handle_message("/start", user: user, bot: bot, understand: response({ "intent" => "Salutation" }))
      handle_message("No", user: user, bot: bot, messages: { "No" => response({"yes_no" => "No"}) })
      handle_message("No", user: user, bot: bot, messages: { "No" => response({"yes_no" => "No"}) })

      messages = bot.messages
      messages.size.should eq(3)
      messages[0][:text].should contain("I would like to ask you a few questions if you have a minute")
      messages[1][:text].should contain("Would you be available later")
      messages[2][:text].should contain("Just say \"hello\" any time if you change your mind")

      user.conversation_step.should eq(nil)
      MvamBot::SurveyResponse.for_user(user.id).size.should eq(0)
    end

    it "should show clarification if response was not understood" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new
      user = Factory::DB.user_with_location

      handle_message("/start", user: user, bot: bot, understand: response({ "intent" => "Salutation" }))
      handle_message("eh?", user: user, bot: bot, understand: response())
      handle_message("ok", user: user, bot: bot, understand: response({ "yes_no" => "Yes" }))

      messages = bot.messages
      messages.size.should eq(3)
      messages[0][:text].should contain("I would like to ask you a few questions if you have a minute")
      messages[1][:text].should eq("Sorry, I did not get that. Can I ask you a few questions now?")
      messages[1][:reply_markup].as(TelegramBot::ReplyKeyboardMarkup).keyboard.flatten.size.should eq(2)
      messages[2][:text].should contain("What's your name?")

      user.conversation_step.not_nil!.should contain("survey/ask_name")
    end

    it "should run failure if response was never understood" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new
      user = Factory::DB.user_with_location

      handle_message("/start", user: user, bot: bot, understand: response({ "intent" => "Salutation" }))
      handle_message("eh?", user: user, bot: bot, understand: response())
      handle_message("uh?", user: user, bot: bot, understand: response())

      messages = bot.messages
      messages.size.should eq(3)
      messages[0][:text].should contain("I would like to ask you a few questions if you have a minute")
      messages[1][:text].should eq("Sorry, I did not get that. Can I ask you a few questions now?")
      messages[1][:reply_markup].as(TelegramBot::ReplyKeyboardMarkup).keyboard.flatten.size.should eq(2)
      messages[2][:text].should contain("Got it, I won't be bothering you")

      user.conversation_step.should eq(nil)
    end

    it "should show default clarification if new text is unspecified" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new
      user = Factory::DB.user_with_location(conversation_step: "survey/ask_roof_photo")

      messages = handle_message("eh?", user: user, bot: bot, understand: response())
      messages[0][:text].should contain("Sorry, I did not understand your reply. Would you please send me a picture of your roof?")

      user.conversation_step.not_nil!.should match(/^survey\/ask_roof_photo\?.*retries=1/)
    end

    it "should move to the next step on an extracted entity" do
      MvamBot::Spec::DB.cleanup
      user = Factory::DB.user_with_location(conversation_step: "survey/ask_age")
      user.conversation_session_id = "TEST_SESSION_ID"

      messages = handle_message("I am 30 years old", user: user)

      messages.size.should eq(1)
      messages[0][:text].should eq("Are you a man or a woman?")

      user.conversation_step.not_nil!.should contain("survey/ask_gender")

      responses = MvamBot::SurveyResponse.for_user(user.id)
      responses.size.should eq(1)

      responses[0].user_id.should eq(user.id)
      responses[0].session_id.should eq(user.conversation_session_id)
      responses[0].data.should eq({ "age" => 30 })
      responses[0].completed.should eq(false)
    end

    it "should extract boolean answer" do
      MvamBot::Spec::DB.cleanup

      user = Factory::DB.user_with_location(conversation_step: "survey/ask_not_enough_food")
      user.conversation_at = Time.utc_now
      user.conversation_session_id = "TEST_SESSION_ID"

      messages = handle_message("Yeah", user: user, messages: { "Yeah" => response({"yes_no" => "Yes"}) })
      messages.size.should eq(1)

      responses = MvamBot::SurveyResponse.for_user(user.id)
      responses.size.should eq(1)
      responses[0].user_id.should eq(user.id)
      responses[0].session_id.should eq(user.conversation_session_id)
      responses[0].data.should eq({ "not_enough_food" => "Yes" })
    end

    it "should extract boolean answer from message" do
      MvamBot::Spec::DB.cleanup

      user = Factory::DB.user_with_location(conversation_step: "survey/ask_not_enough_food")
      user.conversation_at = Time.utc_now
      user.conversation_session_id = "TEST_SESSION_ID"

      messages = handle_message("Yes", user: user)
      messages.size.should eq(1)

      responses = MvamBot::SurveyResponse.for_user(user.id)
      responses.size.should eq(1)
      responses[0].user_id.should eq(user.id)
      responses[0].session_id.should eq(user.conversation_session_id)
      responses[0].data.should eq({ "not_enough_food" => "Yes" })
    end

    it "should end the survey collecting all data" do
      MvamBot::Spec::DB.cleanup

      user = Factory::DB.user_with_location(conversation_step: "survey/ask_feedback")
      user.conversation_state["age"] = 30i64
      user.conversation_state["gender"] = "male"
      user.conversation_state["not_enough_food"] = "Yes"
      user.conversation_session_id = "TEST_SESSION_ID"
      user.conversation_at = Time.utc_now

      messages = handle_message("No", user: user, understand: response({"yes_no" => "No"}))
      messages.last[:text].downcase.should contain("thank you")
      messages.last[:text].downcase.should contain("remember you can send `/price`")

      responses = MvamBot::SurveyResponse.for_user(user.id)
      responses.size.should eq(1)

      responses[0].user_id.should eq(user.id)
      responses[0].session_id.should eq("TEST_SESSION_ID")
      responses[0].data.should eq({ "gender" => "male", "age" => 30, "not_enough_food" => "Yes", "feedback" => "No" })

      user.conversation_step.not_nil!.should contain("thank_you")
    end

    describe "end of survey" do
      it "should not reply to goodbye message right after ending the survey" do
        MvamBot::Spec::DB.cleanup

        user = Factory::DB.user(:with_conversation, conversation_step: "survey/thank_you")
        user.conversation_state["age"] = 30i64
        messages = handle_message("bye", user: user, understand: response({"intent" => "Salutation"}))
        messages.empty?.should be_true

        responses = MvamBot::SurveyResponse.for_user(user.id)
        responses.size.should eq(1)
        responses[0].completed.should eq(true)
      end

      it "should not reply to acknowledge message right after ending the survey" do
        MvamBot::Spec::DB.cleanup

        user = Factory::DB.user(:with_conversation, conversation_step: "survey/thank_you")
        user.conversation_state["age"] = 30i64
        messages = handle_message("ok", user: user, understand: response({"yes_no" => "Yes"}))
        messages.empty?.should be_true

        responses = MvamBot::SurveyResponse.for_user(user.id)
        responses.size.should eq(1)
        responses[0].completed.should eq(true)
      end

      it "should reply to price queries right after ending the survey" do
        MvamBot::Spec::DB.cleanup

        user = Factory::DB.user(:with_conversation, conversation_step: "survey/thank_you")
        user.conversation_state["age"] = 30i64
        messages = handle_message("/price rice", user: user)
        messages.size.should eq(1)
      end
    end

    it "should support asking why and then going back to the survey" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new

      user = Factory::DB.user_with_location(conversation_step: "survey/ask_gender")
      user.conversation_session_id = "TEST_SESSION_ID"
      user.conversation_at = Time.utc_now

      handle_message("Why?", user: user, bot: bot, messages: { "Why?" => response({"intent" => "AskWhy"}) })
      messages = handle_message("Ok", user: user, bot: bot, messages: { "Ok" => response({"yes_no" => "Yes"}) })

      messages.size.should eq(2)
      messages[0][:text].should contain("because we are tracking food security")
      messages[1][:text].should contain("Are you a man or a woman?")

      user.conversation_step.not_nil!.should contain("survey/ask_gender")
    end

    it "should support asking why and who and then going back to the survey" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new

      user = Factory::DB.user_with_location(conversation_step: "survey/ask_gender")
      user.conversation_session_id = "TEST_SESSION_ID"
      user.conversation_at = Time.utc_now

      handle_message("Why?", user: user, bot: bot, messages: { "Why?" => response({"intent" => "AskWhy"}) })
      handle_message("And who are you?", user: user, bot: bot, messages: { "And who are you?" => response({"intent" => "AskWho"}) })
      messages = handle_message("Ok", user: user, bot: bot, messages: { "Ok" => response({"yes_no" => "Yes"}) })

      messages.size.should eq(3)
      messages[0][:text].should contain("because we are tracking food security")
      messages[1][:text].should contain("WFP bot assistant")
      messages[2][:text].should contain("Are you a man or a woman?")

      user.conversation_step.not_nil!.should contain("survey/ask_gender")
    end

    it "should support a picture upload" do
      MvamBot::Spec::DB.cleanup

      user = Factory::DB.user(:with_location, :with_conversation, conversation_step: "survey/ask_roof_photo")
      user.conversation_state["country_name"] = "Algeria"
      messages = handle_message(photo: "myphoto", user: user)

      messages.size.should eq(2)
      messages[0][:text].downcase.should match(/thanks/)

      responses = MvamBot::SurveyResponse.for_user(user.id)
      responses.size.should eq(1)
      responses[0].user_id.should eq(user.id)
      responses[0].data.should eq({"country_name" => "Algeria", "roof_photo" => "photo://myphoto"})

      file = MvamBot::DataFile.find("myphoto").not_nil!
      file.id.should eq("myphoto")
      file.user_id.should eq(user.id)
      file.kind.should eq("image")
      file.extension.should eq("jpg")
      file.data.should_not eq(nil)
    end

    it "should support refusing uploading a picture" do
      MvamBot::Spec::DB.cleanup

      user = Factory::DB.user(:with_location, :with_conversation, conversation_step: "survey/ask_roof_photo")
      user.conversation_state["country_name"] = "Algeria"
      user.conversation_state["gender"] = "male"

      messages = handle_message("no", user: user, messages: { "no" => response({"yes_no" => "No"}) })

      messages.size.should eq(2)
      messages[0][:text].should contain("No problem")
      messages[1][:text].downcase.should contain("would you like to tell us more about")

      responses = MvamBot::SurveyResponse.for_user(user.id)
      responses.size.should eq(1)
      responses[0].data.should eq({"country_name" => "Algeria", "gender" => "male"})
    end

    it "should support a picture upload after a confirmation" do
      MvamBot::Spec::DB.cleanup
      bot = Bot.new

      user = Factory::DB.user(:with_location, :with_conversation, conversation_step: "survey/ask_roof_photo")
      user.conversation_state["country_name"] = "Algeria"
      handle_message("sure", user: user, bot: bot, messages: { "sure" => response({"yes_no" => "Yes"}) })
      messages = handle_message(photo: "myphoto", user: user, bot: bot)

      messages.size.should eq(2)
      messages[0][:text].downcase.should match(/thanks/)
      messages[1][:text].downcase.should contain("would you like to tell us more")

      responses = MvamBot::SurveyResponse.for_user(user.id)
      responses.size.should eq(1)
      responses[0].user_id.should eq(user.id)
      responses[0].data.should eq({ "country_name" => "Algeria", "roof_photo" => "photo://myphoto" })

      file = MvamBot::DataFile.find("myphoto").not_nil!
      file.id.should eq("myphoto")
      file.user_id.should eq(user.id)
      file.kind.should eq("image")
      file.extension.should eq("jpg")
      file.data.should_not eq(nil)
    end

    describe "getting user name" do
      it "asks for user name at survey start" do
        MvamBot::Spec::DB.cleanup
        user = Factory::DB.user(:with_conversation, conversation_step: "survey/start")
        handle_message("Yes", user: user, understand: response({"yes_no" => "Yes"}))

        user.conversation_step.not_nil!.should contain("survey/ask_name")
      end

      context "wit understands contact entity" do
        it "stores contact name and greets user by his name" do
          MvamBot::Spec::DB.cleanup
          user = Factory::DB.user(:with_conversation, conversation_step: "survey/ask_name")

          messages = handle_message("My name is Juan", user: user, understand: response({"contact" => "Juan"}))
          messages.size.should eq(2)
          messages[0][:text].should eq("Nice to meet you, Juan.")

          responses = MvamBot::SurveyResponse.for_user(user.id)
          responses.size.should eq(1)
          responses[0].user_id.should eq(user.id)
          responses[0].data.should eq({"name" => "Juan"})
        end
      end

      context "wit doesn't understand contact entity" do
        it "greets user without name and goes on" do
          MvamBot::Spec::DB.cleanup
          user = Factory::DB.user(:with_conversation, conversation_step: "survey/ask_name")

          messages = handle_message("I don't want to tell you my name", user: user, understand: response())
          messages.size.should eq(2)
          messages[0][:text].should eq("Nice to meet you.")
        end
      end
    end

    describe "local news" do
      context "user is not previously subscribed" do
        context "user country is known" do
          it "should offer news for user's country" do
            MvamBot::Spec::DB.cleanup

            user = Factory::DB.user(:with_location, :with_conversation, conversation_step: "survey/open_question")
            user.conversation_state["country_name"] = "Algeria"
            messages = handle_message("Not really", user: user, understand: response({"yes_no" => "No"}))

            user.conversation_step.not_nil!.should contain("survey/offer_local_news")
            messages.size.should eq(2)
            messages[0][:text].should contain("thank you for your participation")
            messages[1][:text].should contain("food-related news for Algeria")
          end

          it "should store user response" do
            MvamBot::Spec::DB.cleanup

            user = Factory::DB.user(:with_location, :with_conversation, conversation_step: "survey/offer_local_news")
            user.conversation_state["country_name"] = "Algeria"

            handle_message("Yeah", user: user, messages: { "Yeah" => response({"yes_no" => "Yes"}) })

            responses = MvamBot::SurveyResponse.for_user(user.id)
            responses.size.should eq(1)
            responses[0].data["receive_local_news"].should eq("Yes")
          end

          it "should create a subscription if user response postively" do
            MvamBot::Spec::DB.cleanup

            country = MvamBot::Country.find_by_name("Algeria")
            user = Factory::DB.user(:with_location, :with_conversation, conversation_step: "survey/offer_local_news")
            user.conversation_state["country_name"] = country.name

            handle_message("Yeah", user: user, messages: { "Yeah" => response({"yes_no" => "Yes"}) })

            MvamBot::News.subscribed_users(country).should eq([user.id])
          end
        end

        context "user has no country or lat/lng" do
          it "should skip and go to next state" do
            MvamBot::Spec::DB.cleanup

            user = Factory::DB.user(:with_conversation, conversation_step: "survey/ask_roof_photo")
            messages = handle_message(photo: "myphoto", user: user)

            user.conversation_step.not_nil!.should contain("survey/open_question")
          end
        end
      end

      context "user is previously subscribed" do
        it "should to straight to next step" do
          MvamBot::Spec::DB.cleanup

          country = MvamBot::Country.find_by_name("Algeria")

          user = Factory::DB.user(:with_location, :with_conversation, conversation_step: "survey/ask_roof_photo")
          user.conversation_state["country_name"] = country.name
          MvamBot::News.subscribe(country, user)

          handle_message(photo: "myphoto", user: user)
          user.conversation_step.not_nil!.should contain("survey/open_question")
        end
      end
    end

    describe "open ended question" do
      it "asks open ended question" do
        MvamBot::Spec::DB.cleanup
        user = Factory::DB.user(:with_conversation, conversation_step: "survey/ask_roof_photo")

        messages = handle_message("No", user: user, understand: response({"yes_no" => "No"}))
        user.conversation_step.not_nil!.should contain("survey/open_question")

        messages.last[:text].downcase.should contain("would you like to tell us more")
      end

      it "stores user user open message if any" do
        MvamBot::Spec::DB.cleanup
        user = Factory::DB.user(:with_conversation, conversation_step: "survey/open_question")
        message = "Food situation is really bad over here..."

        handle_message(message, user: user, understand: response())

        responses = MvamBot::SurveyResponse.for_user(user.id)
        responses[0].data["message"].should eq(message)
      end

      it "stores negative answers" do
        MvamBot::Spec::DB.cleanup
        user = Factory::DB.user(:with_conversation, conversation_step: "survey/open_question")

        handle_message("No", user: user, understand: response({"yes_no" => "No"}))

        responses = MvamBot::SurveyResponse.for_user(user.id)
        responses[0].data["message"].should eq("No")
      end
    end

    describe "asking for feedback" do
      it "asks if survey was helpful before ending survey" do
        MvamBot::Spec::DB.cleanup
        user = Factory::DB.user(:with_conversation, conversation_step: "survey/open_question")

        messages = handle_message("No", user: user, understand: response({"yes_no" => "No"}))
        user.conversation_step.not_nil!.should contain("survey/ask_feedback")

        messages.last[:text].downcase.should contain("do you have any suggestions?")
      end

      it "stores user feedback if any" do
        MvamBot::Spec::DB.cleanup
        user = Factory::DB.user(:with_conversation, conversation_step: "survey/ask_feedback")

        feedback = "I didn't like this and that..."
        messages = handle_message(feedback, user: user, understand: response())
        user.conversation_step.not_nil!.should contain("survey/thank_you")

        responses = MvamBot::SurveyResponse.for_user(user.id)
        responses[0].data["feedback"].should eq(feedback)
      end

      it "stores negative answers" do
        MvamBot::Spec::DB.cleanup
        user = Factory::DB.user(:with_conversation, conversation_step: "survey/ask_feedback")

        handle_message("No", user: user, understand: response({"yes_no" => "No"}))

        responses = MvamBot::SurveyResponse.for_user(user.id)
        responses[0].data["feedback"].should eq("No")
      end
    end

    describe "geolocation" do
      context "user with previously known lat/lng" do
        it "should skip asking user for location if known position is recent enough" do
          MvamBot::Spec::DB.cleanup
          user = Factory::DB.user(conversation_step: "survey/ask_how_you_doing", location_lat: 10.0, location_lng: 20.0, gps_timestamp: 1.day.ago)
          user.conversation_session_id = "TEST_SESSION_ID"

          handle_message("fine", user: user, understand:  response())
          user.conversation_step.not_nil!.should contain("survey/ask_age")

          responses = MvamBot::SurveyResponse.for_user(user.id)
          responses[0].data["lat"].should eq(user.location_lat)
          responses[0].data["lng"].should eq(user.location_lng)
        end

        it "should ask the user if his position has changed if known position is not recent enough" do
          MvamBot::Spec::DB.cleanup
          user = Factory::DB.user(conversation_step: "survey/ask_how_you_doing", location_lat: 10.0, location_lng: 20.0, gps_timestamp: 1.week.ago)
          user.conversation_session_id = "TEST_SESSION_ID"

          geocoder = Geocoder.new
          geocoder.expect_reverse_lookup(10.0, 20.0) { {country_name: "Argentina", label: "Buenos Aires"} }

          messages = handle_message(user: user, understand: response(), geocoder: geocoder)
          user.conversation_step.not_nil!.should contain("survey/ask_location_changed")

          messages.last[:text].should eq("Are you still in Buenos Aires?")

          responses = MvamBot::SurveyResponse.for_user(user.id)
        end
      end

      context "user without previously known lat/lng" do
        it "should ask for gps access" do
          MvamBot::Spec::DB.cleanup
          user = Factory::DB.user(conversation_step: "survey/ask_how_you_doing")
          user.conversation_session_id = "TEST_SESSION_ID"

          messages = handle_message(user: user, understand: response() )
          reply_buttons(messages.last).should eq(["Sure", "I'd rather not"])
          user.conversation_step.not_nil!.should contain("survey/ask_gps")
        end

        context "user shares gps position" do
          it "should continue to next step if user shares gps position" do
            MvamBot::Spec::DB.cleanup
            user = Factory::DB.user(conversation_step: "survey/ask_gps")
            user.conversation_session_id = "TEST_SESSION_ID"

            messages = handle_message("", user: user, location: {10.0, 20.0})
            messages.size.should eq(1)
            user.conversation_step.not_nil!.should contain("survey/ask_age")

            responses = MvamBot::SurveyResponse.for_user(user.id)
            responses[0].data.should eq({"lat" => 10.0, "lng" => 20.0})
          end
        end

        context "if user refuses to share gps position" do
          context "user's country is known" do
            it "should ask for location name for geocoding" do
              MvamBot::Spec::DB.cleanup
              user = Factory::DB.user_with_location(conversation_step: "survey/ask_gps")
              user.conversation_session_id = "TEST_SESSION_ID"
              adm0_name = MvamBot::Location::Adm0.find(user.location_adm0_id.not_nil!).name

              messages = handle_message("I'd rather not", user: user)
              messages[0][:text].should eq("What's the name of your town?")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses[0].data.should eq({"country_name" => adm0_name})

              user.conversation_step.not_nil!.should contain("survey/ask_location_name")
            end
          end

          context "user's country is not known" do
            it "should ask the user to select his country if we don't know it yet" do
              MvamBot::Spec::DB.cleanup
              user = Factory::DB.user(conversation_step: "survey/ask_gps")
              user.conversation_session_id = "TEST_SESSION_ID"

              messages = handle_message("I'd rather not", user: user)
              messages.size.should eq(1)
              messages[0][:text].should eq("What country do you live in?")
              reply_buttons(messages[0]).should eq(MvamBot::Country.all_names)

              user.conversation_step.not_nil!.should contain("survey/ask_country")
            end

            it "should store selected country and ask for location name after country selection" do
              MvamBot::Spec::DB.cleanup
              user = Factory::DB.user(conversation_step: "survey/ask_country")
              user.conversation_session_id = "TEST_SESSION_ID"

              selected_country = MvamBot::Country.all.first

              messages = handle_message(selected_country.name, user: user)
              messages[0][:text].should eq("What's the name of your town?")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses[0].data.should eq({"country_name" => selected_country.name})

              user.conversation_step.not_nil!.should contain("survey/ask_location_name")
            end
          end

          context "geolocation yields a single result" do
            it "should store response and continue to next question" do
              MvamBot::Spec::DB.cleanup
              user = Factory::DB.user(conversation_step: "survey/ask_location_name")
              user.conversation_session_id = "TEST_SESSION_ID"
              user.conversation_state["country_name"] = "Argentina"

              geocoder = Geocoder.new
              geocoder.expect_lookup("Buenos Aires", "Argentina") { {"Buenos Aires, Argentina" => {10.0, 20.0}} }

              messages = handle_message("I live in Buenos Aires",
                                        user: user,
                                        understand: response({"location" => "Buenos Aires"}),
                                        geocoder: geocoder)

              messages.size.should eq(1)
              user.conversation_step.not_nil!.should contain("survey/ask_age")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses[0].data.should eq({
                "lat" => 10.0,
                "lng" => 20.0,
                "location_name" => "Buenos Aires",
                "country_name" => "Argentina"
              })
            end
          end

          context "geolocation yields no result" do
            it "continue to next question" do
              MvamBot::Spec::DB.cleanup
              user = Factory::DB.user(conversation_step: "survey/ask_location_name")
              user.conversation_session_id = "TEST_SESSION_ID"
              user.conversation_state["country_name"] = "Argentina"

              messages = handle_message("I live in Buenos Aires",
                                        user: user,
                                        messages: { "I live in Buenos Aires" => response({"location" => "Buenos Aires"}) })

              messages.size.should eq(1)
              user.conversation_step.not_nil!.should contain("survey/ask_age")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses[0].data.should eq({"location_name" => "Buenos Aires", "country_name" => "Argentina"})
            end

          end

          context "geolocation yields multiple results" do
            it "asks the user to select his real location" do
              MvamBot::Spec::DB.cleanup
              user = Factory::DB.user(conversation_step: "survey/ask_location_name")
              user.conversation_session_id = "TEST_SESSION_ID"
              user.conversation_state["country_name"] = "Argentina"

              geocoder = Geocoder.new
              geocoder.expect_lookup("Buenos Aires", "Argentina") do
                {
                  "Ciudad de Buenos Aires, Argentina" => {10.0, 20.0},
                  "Provincia de Buenos Aires, Argentina" => {15.0, 20.0}
                }
              end

              messages = handle_message("I live in Buenos Aires",
                                        user: user,
                                        understand: response({"location" => "Buenos Aires"}),
                                        geocoder: geocoder)

              user.conversation_step.not_nil!.should contain("survey/ask_which_location")

              messages.size.should eq(1)
              reply_buttons(messages[0]).should eq([
                "Ciudad de Buenos Aires, Argentina",
                "Provincia de Buenos Aires, Argentina",
                "None of the above"
              ])

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses[0].data["location_name"].should eq("Buenos Aires")
            end

            it "stores position of selected geolocation result" do
              MvamBot::Spec::DB.cleanup
              user = Factory::DB.user(conversation_step: "survey/ask_which_location")
              user.conversation_session_id = "TEST_SESSION_ID"
              user.conversation_state["country_name"] = "Argentina"
              user.conversation_state["location_name"] = "Buenos Aires"

              # TODO: This second lookup could be avoided by persisting all results in conversation state
              geocoder = Geocoder.new
              geocoder.expect_lookup("Buenos Aires", "Argentina") do
                {
                  "Ciudad de Buenos Aires, Argentina" => {10.0, 20.0},
                  "Provincia de Buenos Aires, Argentina" => {15.0, 20.0}
                }
              end

              handle_message("Ciudad de Buenos Aires, Argentina", user: user, geocoder: geocoder)

              user.conversation_step.not_nil!.should contain("survey/ask_age")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses[0].data["lat"].should eq(10.0)
              responses[0].data["lng"].should eq(20.0)
            end
          end
        end
      end
    end

    it "presets user administrative location when obtained lat/lng is close tu a known mkt" do
      MvamBot::Spec::DB.cleanup
      Location.create_test_locations

      user = Factory::DB.user(conversation_step: "survey/ask_gps")
      user.conversation_session_id = "TEST_SESSION_ID"
      mkt = Location.vicente_lopez

      handle_message("", user: user, location: {mkt.lat.not_nil!, mkt.lng.not_nil!})

      user.location_lat.should eq(mkt.lat)
      user.location_lng.should eq(mkt.lng)
      user.gps_timestamp.should_not be_nil

      user.location_mkt_id.should eq(mkt.id)
      user.location_adm1_id.should eq(mkt.adm1_id)
      user.location_adm0_id.should eq(mkt.adm0_id)
    end

    describe "coping question" do
      context "positive answer" do
        it "ask user how many days he needed help" do
          MvamBot::Spec::DB.cleanup

          user = Factory::DB.user(conversation_step: "survey/ask_not_enough_food")
          messages = handle_message("Yes", user: user)

          user.conversation_step.not_nil!.should contain("ask_days_needed_help")
          messages.last[:text].downcase.should contain("how many days did your household borrow food")
        end

        it "stores interpreted number if available" do
          MvamBot::Spec::DB.cleanup

          user = Factory::DB.user(conversation_step: "survey/ask_days_needed_help")
          messages = handle_message("about 3 days", user: user)

          user.conversation_step.not_nil!.should contain("ask_roof_photo")

         responses = MvamBot::SurveyResponse.for_user(user.id)
         responses.size.should eq(1)
         responses[0].data["days_needed_help"].should eq(3)
        end

        it "stores raw answer if cannot interpret commodity" do
          MvamBot::Spec::DB.cleanup

          user = Factory::DB.user(conversation_step: "survey/ask_days_needed_help")
          messages = handle_message("about three days", user: user, understand: response())

          user.conversation_step.not_nil!.should contain("ask_roof_photo")

          responses = MvamBot::SurveyResponse.for_user(user.id)
          responses.size.should eq(1)
          responses[0].data["days_needed_help"].should eq("about three days")
        end
      end

      context "negative answer" do
        it "goes on to next question" do
          MvamBot::Spec::DB.cleanup

          user = Factory::DB.user(conversation_step: "survey/ask_not_enough_food")
          handle_message("No", user: user, understand: response())

          user.conversation_step.not_nil!.should contain("ask_roof_photo")
        end
      end

    end

    describe "asking for local prices" do
      context "user lat/lng not available" do
        it "proceeds to next step if there is no position available" do
          MvamBot::Spec::DB.cleanup
          user = Factory::DB.user(conversation_step: "survey/ask_not_enough_food")
          user.conversation_session_id = "TEST_SESSION_ID"

          handle_message("No", user: user, understand: response())
          user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")
        end
      end

      describe "determining requested currency" do
        it "infers currency from reported country name if available" do
          MvamBot::Spec::DB.cleanup

          user = user_near mkt_id: 496, conversation_step: "survey/ask_not_enough_food"
          user.conversation_state["country_name"] = "Ethiopia"

          messages = handle_message("No", user: user, understand: response())
          messages.size.should eq(1)
          messages[0][:text].should contain("Reply with the price of 1 KG in ethiopian birrs")
        end

        it "reverse geocodes lat/lng if necessary to obtain country" do
          MvamBot::Spec::DB.cleanup
          user = user_near mkt_id: 496, conversation_step: "survey/ask_not_enough_food"

          geocoder = Geocoder.new
          geocoder.expect_user_position_lookup(user) { {country_name: "Ethiopia", label: "Addis Ababa"} }

          messages = handle_message("No", user: user, geocoder: geocoder, understand: response())
          messages.size.should eq(1)
          messages[0][:text].should contain("Reply with the price of 1 KG in ethiopian birrs")
        end

        it "skips asking if currency could not be determined due to unknown country name" do
          MvamBot::Spec::DB.cleanup
          user = user_near mkt_id: 496, conversation_step: "survey/ask_not_enough_food"
          user.conversation_state["country_name"] = "foo bar"

          handle_message("No", user: user, understand: response())
          user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")
        end

        it "skips asking if currency could not be determined due to failed reverse geocoding" do
          MvamBot::Spec::DB.cleanup
          user = user_near mkt_id: 496, conversation_step: "survey/ask_not_enough_food"

          geocoder = Geocoder.new
          geocoder.expect_user_position_lookup(user) { nil }

          handle_message("No", user: user, understand: response())
          user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")
        end
      end

      describe "determining requested commodity" do
        context "user is located near a known mkt" do
          it "asks for any commodity of that mkt" do
            MvamBot::Spec::DB.cleanup

            # mkt with multiple products
            user = user_near mkt_id: 496, conversation_step: "survey/ask_not_enough_food"
            user.conversation_state["country_name"] = "Afghanistan"

            messages = handle_message("No", user: user, understand: response())
            verify_asked_commodity(messages[0], ["wheat", "rice (low quality)"])
          end
        end

        context "user is not located near a known mkt" do
          it "asks for any commodity in the user's country when it matches a known Adm0" do
            MvamBot::Spec::DB.cleanup

            user = Factory::DB.user(conversation_step: "survey/ask_not_enough_food")
            user.conversation_session_id = "TEST_SESSION_ID"

            # middle of the atlantic
            user.conversation_state["lat"] = -19.469574
            user.conversation_state["lng"] = -17.046498
            user.conversation_state["country_name"] = "Afghanistan"

            messages = handle_message("No", user: user, understand: response())

            country_commodities = MvamBot::DB.db.query_all("SELECT DISTINCT(commodity_name) FROM prices WHERE location_adm0_id = 1", as: {String}).map(&.downcase)
            verify_asked_commodity(messages[0], country_commodities)
          end

          it "asks for a random commodity when user's country does not match a known Adm0" do
            MvamBot::Spec::DB.cleanup
            user = Factory::DB.user(conversation_step: "survey/ask_not_enough_food")
            user.conversation_session_id = "TEST_SESSION_ID"
            user.conversation_state["lat"] = -15.583478
            user.conversation_state["lng"] = -41.307781
            user.conversation_state["country_name"] = "Brazil"

            messages = handle_message("No", user: user, understand: response())

            messages[0][:text].should match(/how much does .* cost/)
            asked_currency(messages[0]).should eq("brazilian reals")
          end

          it "asks for a random commodity when users' country does not match a known Adm0 and no lat/lng is known" do
            MvamBot::Spec::DB.cleanup
            user = Factory::DB.user(conversation_step: "survey/ask_not_enough_food")
            user.conversation_state["country_name"] = "Brazil"
            user.conversation_session_id = "TEST_SESSION_ID"

            messages = handle_message("No", user: user, understand: response())
            messages[0][:text].should match(/how much does .* cost/)
            asked_currency(messages[0]).should eq("brazilian reals")
          end
        end

      end

      it "stores requested commodity and currency after asking" do
        MvamBot::Spec::DB.cleanup

        # mkt with single price
        user = user_near mkt_id: 496, conversation_step: "survey/ask_not_enough_food"
        user.conversation_state["country_name"] = "Afghanistan"

        handle_message("No", user: user, understand: response())
        user.conversation_step.not_nil!.should contain("survey/ask_local_price")

        reference_price = MvamBot::Price.sample_in_mkt(496)
        responses = MvamBot::SurveyResponse.for_user(user.id)
        responses.size.should eq(1)
        responses[0].data["asked_price_currency_code"].should eq("AFN")
        responses[0].data["asked_price_commodity_id"].should eq(reference_price.commodity_id)
      end

      describe "processing answer" do
        context "answer is close tu reference price" do
          it "stores user answer" do
            MvamBot::Spec::DB.cleanup

            user = user_near mkt_id: 496, conversation_step: "survey/ask_local_price"
            user.conversation_state["country_name"] = "Afghanistan"

            reference_price = MvamBot::Price.sample_in_mkt(496)
            answer = reference_price.price * 1.5
            handle_message("About #{answer} AFN", user: user)

            user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")

            responses = MvamBot::SurveyResponse.for_user(user.id)
            responses.size.should eq(1)
            responses[0].data["asked_price_answer"].should eq(answer)
            responses[0].data["price_certainty"].should eq("unconfirmed")
          end
        end

        it "accepts fractional numbers written with comma" do
          MvamBot::Spec::DB.cleanup

          user = user_near mkt_id: 496, conversation_step: "survey/ask_local_price"
          user.conversation_state["country_name"] = "Afghanistan"

          reference_price = MvamBot::Price.sample_in_mkt(496)
          answer = reference_price.price * 1.5
          answer_txt = answer.to_s.gsub(".", ",")
          handle_message("About #{answer_txt} AFN", user: user)

          user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")

          responses = MvamBot::SurveyResponse.for_user(user.id)
          responses.size.should eq(1)
          responses[0].data["asked_price_answer"].as(Float64).should be_close(answer, 0.001)
          responses[0].data["price_certainty"].should eq("unconfirmed")
        end

        context "answer is considerably different from reference price" do
          context "user currency matches reference price" do
            it "confirms reported price with the user" do
              MvamBot::Spec::DB.cleanup

              user = user_near mkt_id: 496, conversation_step: "survey/ask_local_price"
              user.conversation_state["country_name"] = "Ethiopia"

              reference_price = MvamBot::Price.sample_in_mkt(496)
              answer = reference_price.price * 5

              messages = handle_message("About #{answer} AFN", user: user)

              user.conversation_step.not_nil!.should contain("survey/confirm_local_price")
              messages[0][:text].should contain("are you sure")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses.size.should eq(1)
              responses[0].data["asked_price_answer"].should eq(answer)
            end

            it "overrides original answer if user responds with a different amount after confirmation" do
              MvamBot::Spec::DB.cleanup

              user = user_near mkt_id: 496, conversation_step: "survey/confirm_local_price"
              user.conversation_state["asked_price_answer"] = 300.to_i64

              handle_message("Oops! Typo! It's actually 30.", user: user)
              user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses.size.should eq(1)
              responses[0].data["asked_price_answer"].should eq(30)
              responses[0].data["price_certainty"].should eq("confirmed")
            end

            it "continues to next step and leaves original value if user responds he is sure" do
              MvamBot::Spec::DB.cleanup

              user = user_near mkt_id: 496, conversation_step: "survey/confirm_local_price"
              user.conversation_state["asked_price_answer"] = 300.to_i64

              handle_message("No", user: user, understand: response({"yes_no" => "Yes"}))
              user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses.size.should eq(1)
              responses[0].data["asked_price_answer"].should eq(300)
              responses[0].data["price_certainty"].should eq("confirmed")
            end

            it "continues to next step and leaves original value if user responds he is not sure" do
              MvamBot::Spec::DB.cleanup

              user = user_near mkt_id: 496, conversation_step: "survey/confirm_local_price"
              user.conversation_state["asked_price_answer"] = 300.to_i64

              messages = handle_message("No", user: user, understand: response({"yes_no" => "No"}))
              user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses.size.should eq(1)
              responses[0].data["asked_price_answer"].should eq(300)
              responses[0].data["price_certainty"].should eq("not_sure")
            end
          end

          context "user currency differs from reference price" do
            it "continues to next step even reference price is not in the same currency as user" do
              MvamBot::Spec::DB.cleanup

              # nearby market in Ethiopia but user currency is from Somalia
              user = user_near mkt_id: 496, conversation_step: "survey/ask_local_price"
              user.conversation_state["country_name"] = "Somalia"

              reference_price = MvamBot::Price.sample_in_mkt(496)

              messages = handle_message("About #{10000000} AFN", user: user)

              user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")

              responses = MvamBot::SurveyResponse.for_user(user.id)
              responses.size.should eq(1)
              responses[0].data["asked_price_answer"].should eq(10000000)
            end
          end

          # JSON from Wit could return both integer and floats for number entities, we should support both
          it "supports integer responses" do
            MvamBot::Spec::DB.cleanup

            user = user_near mkt_id: 496, conversation_step: "survey/ask_local_price"
            user.conversation_state["country_name"] = "Afghanistan"

            reference_price = MvamBot::Price.sample_in_mkt(496)
            answer = reference_price.price.to_i

            handle_message("About #{answer} AFN", user: user)

            user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")
          end
        end
      end


      it "moves to next step if user responds in a negative way" do
        MvamBot::Spec::DB.cleanup

        user = user_near mkt_id: 496, conversation_step: "survey/ask_local_price"
        user.conversation_state["country_name"] = "Afghanistan"

        handle_message("We don't have that in my town", user: user, understand: response({"yes_no" => "No"}))
        user.conversation_step.not_nil!.should contain("survey/ask_roof_photo")
      end

    end
  end

end

def user_near(mkt_id : Int32, conversation_step : String)
  user = Factory::DB.user(conversation_step: conversation_step)
  user.conversation_session_id = "TEST_SESSION_ID"
  mkt = MvamBot::Location::Mkt.find(mkt_id)

  # set user position near a known market
  lat, lng = { (mkt.lat.not_nil! + 0.01), (mkt.lng.not_nil! - 0.01) }
  user.conversation_state["lat"] = lat
  user.conversation_state["lng"] = lng
  user
end

def asked_commodity(message)
  /how much does (.*) cost/.match(message[:text]).not_nil![1]
end

def asked_currency(message)
  /Reply with the price of 1 .* in (.*)\./.match(message[:text]).not_nil![1]
end

def verify_asked_commodity(message, accepted_commodities)
  accepted_commodities.includes?(asked_commodity(message)).should be_true
end
