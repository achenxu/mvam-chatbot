module MvamBot

  class SurveyResponse

    alias SurveyData = Hash(String, Bool | Float64 | Int64 | String | Nil)

    property id : Int64?
    property user_id : Int32
    property session_id : String
    property data : SurveyData
    property completed : Bool
    property timestamp : Time

    FIELD_TYPES = { Int64, Int32, String, String, Bool, Time }
    FIELD_NAMES = %w(id user_id session_id data completed timestamp)

    def initialize(@id : Int64?, @user_id : Int32, @session_id : String, @data : SurveyData = SurveyData.new, @completed : Bool = false, @timestamp : Time = Time.utc_now)
    end

    def initialize(@id : Int64?, @user_id : Int32, @session_id : String, data_json : String, @completed : Bool = false, @timestamp : Time = Time.utc_now)
      @data = SurveyData.new.tap do |state|
        if json = data_json
          JSON.parse(json).as_h.each do |key, value|
            case value
            when Bool then state[key] = value
            when Float64 then state[key] = value
            when Int64 then state[key] = value
            when String then state[key] = value
            end
          end
        end
      end
    end

    def self.save_response(user_id : Int32, session_id : String, data : SurveyData, completed : Bool = false, timestamp : Time = Time.utc_now)
      id = DB.db.scalar(
        "INSERT INTO survey_responses (user_id, session_id, data, completed, timestamp)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (session_id) DO UPDATE SET data = EXCLUDED.data, completed = EXCLUDED.completed, timestamp = EXCLUDED.timestamp
         RETURNING id",
         [user_id, session_id, data.to_json, completed, timestamp]).as(Int64)
      SurveyResponse.new(id, user_id, session_id, data, completed, timestamp)
    end

    def self.find(id)
      result = DB.db.query_one?("SELECT #{FIELD_NAMES.join(", ")} FROM survey_responses WHERE id = $1", [id], as: FIELD_TYPES)
      return nil if result.nil?
      self.new(*result)
    end

    def self.for_user(user_id)
      DB.db.query_all("SELECT #{FIELD_NAMES.join(", ")} FROM survey_responses WHERE user_id = $1 ORDER BY timestamp DESC", [user_id], as: FIELD_TYPES).map{|r| self.new(*r)}
    end

    def self.all
      DB.db.query_all("SELECT #{FIELD_NAMES.join(", ")} FROM survey_responses ORDER BY timestamp DESC", as: FIELD_TYPES).map{|r| self.new(*r)}
    end

  end

end
