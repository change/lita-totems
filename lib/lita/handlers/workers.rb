require 'sidekiq'
require 'lita'
require "lita/handlers/stats"

module Lita
  module Handlers
    class Timeout
      include Sidekiq::Job

      def initialize
        Sidekiq.redis do |connection| 
          @redis_namespace = Redis::Namespace.new("lita:handlers:#{Totems.namespace}", redis: connection)
        end
      end

      def take_totem(totem, user_id, timeout)
        @redis_namespace.set("totem/#{totem}/owning_user_id", user_id)
        @redis_namespace.sadd("user/#{user_id}/totems", totem)
        @redis_namespace.hset("totem/#{totem}/waiting_since", user_id, Time.now.to_i)
        timeout_job = Timeout.perform_in(timeout, user_id, totem)
        @redis_namespace.hset("totem/#{totem}/timeout_jobs", user_id, timeout_job.jid)
      end

      def yield_totem(totem, user_id)
        waiting_since_hash = @redis_namespace.hgetall("totem/#{totem}/waiting_since")
        Stats.capture_holding_time(totem, waiting_since_hash[user_id])    

        @redis_namespace.srem("user/#{user_id}/totems", totem)
        @redis_namespace.hdel("totem/#{totem}/waiting_since", user_id)
        @redis_namespace.hdel("totem/#{totem}/message", user_id)
        @redis_namespace.hdel("totem/#{totem}/timeout", user_id)
        @redis_namespace.srem("user/#{user_id}/totems/reminder", totem) if @redis_namespace.smembers("user/#{user_id}/totems/reminder").include?(totem)
        next_user_id = @redis_namespace.lpop("totem/#{totem}/list")
        if next_user_id
          timeout_hash = @redis_namespace.hgetall("totem/#{totem}/timeout")
          Stats.capture_waiting_time(totem, waiting_since_hash[next_user_id])
          take_totem(response, totem, next_user_id, timeout_hash[next_user_id].to_i)
          next_user = Lita::User.find_by_id(next_user_id)
          queue_size = @redis_namespace.llen("totem/#{totem}/list")
          @redis_namespace.hset("totem/#{totem}/timeout_messages", next_user_id, %{You are now in possession of totem "#{totem}", yielded by #{response.user.name}. There are #{queue_size} people in line after you.})
          @redis_namespace.hset("totem/#{totem}/timeout_messages", user_id, %{Your totem "#{totem}", expired and has been given to #{next_user.name}.})
        else
          @redis_namespace.del("totem/#{totem}/owning_user_id")
          @redis_namespace.hset("totem/#{totem}/timeout_messages", user_id, %{Your totem "#{totem}" has expired.})
        end
      end

      def get_user_by_id(user_id)
        # This query by user_id is needed because if we take the user
        # from the response, then it will always be the user that first timed out
        Lita::User.find_by_id(user_id)
      end

      def notify()
      end

      def perform(totem, user_id)
        yield_totem(totem, user_id)
      end
    end
  end
end
