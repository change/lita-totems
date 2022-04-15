require 'lita'
require 'chronic_duration'
require 'redis-semaphore'
require "lita/handlers/stats"
module Lita
  module Handlers
    class Totems < Handler

      @@DemoEnvironments = %w(cyan jade noir opal plum teal vert)
      @@EnvironmentToSlackChannelMap = {
        teal:"#pd-teal-deploys",
        jade:"#pd-pacific-deploys",
        noir:"#pd-contributor-demos",
        opal:"#pd-contributor-demos",
        vert:"#pd-contributor-demos",
        cyan:"#demo-deployment-cyan",
        plum:"#squad-integrity",
        corgi:"#pd-release-corgi",
        fe:"#pd-release-fe",
        user_service:"#pd-release-user-service",
        petition_service:"#pd-release-petition-service",
        payment_service:"#pd-release-payment-service",
        comms_stack:"#pd-release-comms-stack",
        signature_service:"#pd-release-signature-service",
        hammer:"#pd-deployment",
        mallet:"#pd-deployment",
        etl_extract:"#squad-data-platform"
      }

      def self.route_regex(action_capture_group)
        %r{
        ^totems?\s+
        (#{action_capture_group})\s+
        (?<totem>\w+)\s*
        (?<message>.*)?
        }x
      end

      route(
        %r{
        ^totems?\s+
        (add|join|take|queue)\s+
        (?<totem>\w+)\s*
        ((?<message>((?!timeout:).)*)\s*)?
        (timeout:\s?(?<timeout>\d+))?
        }x,
        :add,
          help: {
            'totems add TOTEM <MESSAGE> timeout: <TIMEOUT?' => "Adds yourself to the TOTEM queue, or assigns yourself to the TOTEM if it's unassigned. Includes optional MESSAGE and optional TIMEOUT."
      })

      route(
        %r{
        ^totems?\s+
        (yield|finish|leave|done|complete|remove)
        (\s+(?<totem>\w+))?
        }x,
        :yield,
        help: {
          'totems yield TOTEM' => 'Yields the TOTEM.  If you are in the queue for the totem, leaves the queue.'
        })

      route(route_regex("create"), :create,
            help: {
              'totems create TOTEM' => 'Creates a new totem TOTEM.'
            })

      route(route_regex("destroy|delete"), :destroy,
            help: {
              'totems destroy TOTEM' => 'Destroys totem TOTEM.'
            })

      route(route_regex("kick"),
            :kick,
            help: {
              'totems kick TOTEM' => 'Kicks the user currently in possession of the TOTEM off.',
            })

      route(
        %r{
            ^totems?
            (\s+info?
              (\s+(?<totem>\w+))?
            )?
            $
            }x,
        :info,
        help: {
          'totems info'       => "Shows info of all totems queues",
          'totems info TOTEM' => 'Shows info of just one totem'
        })

      route(
        %r{
        ^totems?
        \s+get?
        \s+stats?
        }x,
        :stats,
        help: {
          'totems get stats' => "Get totem's stats SignalFX link",
        })

      def destroy(response)
        totem = response.match_data[:totem]
        if redis.exists "totem/#{totem}"
          redis.del("totem/#{totem}")
          redis.del("totem/#{totem}/list")
          redis.srem("totems", totem)
          owning_user_id = redis.get("totem/#{totem}/owning_user_id")
          redis.srem("user/#{owning_user_id}/totems", totem) if owning_user_id
          redis.del("totem/#{totem}/waiting_since")
          redis.del("totem/#{totem}/message")
          response.reply(%{Destroyed totem "#{totem}".})
        else
          response.reply(%{Error: totem "#{totem}" doesn't exist.})
        end
      end

      def create(response)
        totem = response.match_data[:totem]

        if redis.exists "totem/#{totem}"
          response.reply %{Error: totem "#{totem}" already exists.}
        else
          redis.set("totem/#{totem}", 1)
          redis.sadd("totems", totem)
          response.reply %{Created totem "#{totem}".}
        end

      end

      def add(response)
        totem = response.match_data[:totem]
        unless redis.exists "totem/#{totem}"
          response.reply %{Error: there is no totem "#{totem}".}
          return
        end

        user_id = response.user.id

        if queued_by_user(user_id).include?(totem)
          response.reply %{Error: you are already in the queue for "#{totem}".}
          return
        end

        if redis.smembers("user/#{user_id}/totems").include?(totem)
          response.reply %{Error: you already have the totem "#{totem}".}
          return
        end

        Stats.capture_totem_use(totem)
        message = response.match_data[:message].strip
        timeout = response.match_data[:timeout]
        if !timeout.nil? && timeout != '0'
          timeout = timeout.to_i
          timeout = 24 if timeout == 0
        else
          timeout = 24
        end

        token_acquired = false
        queue_size     = nil
        Redis::Semaphore.new("totem/#{totem}", redis: redis).lock do
          redis.hset("totem/#{totem}/message", user_id, message) if message && message != ""
          redis.hset("totem/#{totem}/timeout", user_id, timeout) if @@DemoEnvironments.include?(totem)
          if redis.llen("totem/#{totem}/list") == 0 && redis.get("totem/#{totem}/owning_user_id").nil?
            # take it:
            token_acquired = true
            take_totem(response, totem, user_id, timeout)
          else
            # queue:
            queue_size = redis.rpush("totem/#{totem}/list", user_id)
            redis.hset("totem/#{totem}/waiting_since", user_id, Time.now.to_i)
            current_owner_id = redis.get("totem/#{totem}/owning_user_id")
            unless redis.sismember("user/#{current_owner_id}/totems/reminder", totem)
              robot.send_messages(Lita::Source.new(user: Lita::User.find_by_id(current_owner_id)), %{#{response.user.name} just added the "#{totem}" totem, are you still using it?})
              redis.sadd("user/#{current_owner_id}/totems/reminder", totem)
            end
          end
        end
        
        if token_acquired
          # TODO don't readd to totems you are already waiting for!
          response.reply(%{#{response.user.name}, you now have totem "#{totem}".})
        else
          Stats.capture_people_waiting(totem, queue_size)
          response.reply(%{#{response.user.name}, you are \##{queue_size} in line for totem "#{totem}".})
        end

      end

      def yield(response)
        user_id               = response.user.id
        totems_owned_by_user  = redis.smembers("user/#{user_id}/totems")
        totems_queued_by_user = queued_by_user(user_id)
        if totems_owned_by_user.empty? && totems_queued_by_user.empty?
          response.reply "Error: You do not have any totems to yield."
        elsif totems_owned_by_user.size == 1 && !response.match_data[:totem] && totems_queued_by_user.empty?
          yield_totem(totems_owned_by_user[0], user_id, response)
        else
          totem_specified = response.match_data[:totem]
          # if they don't specify and are only queued for a single totem, yield that one
          totem_specified = totems_queued_by_user.first if !totem_specified && totems_queued_by_user.size == 1 && totems_owned_by_user.empty?
          if totem_specified
            if totems_owned_by_user.include?(totem_specified)
              yield_totem(totem_specified, user_id, response)
            elsif totems_queued_by_user.include?(totem_specified)
              redis.lrem("totem/#{totem_specified}/list", 0, user_id)
              redis.hdel("totem/#{totem_specified}/waiting_since", user_id)
              redis.hdel("totem/#{totem_specified}/message", user_id)
              redis.hdel("totem/#{totem_specified}/timeout", user_id)
              response.reply("You are no longer in line for the \"#{totem_specified}\" totem.")
            else
              response.reply %{Error: You don't own and aren't waiting for the "#{totem_specified}" totem.}
            end
          else
            response.reply "You must specify a totem to yield.  Totems you own: #{totems_owned_by_user.sort}.  Totems you are in line for: #{totems_queued_by_user.sort}."
          end
        end
      end

      def kick(response)
        totem = response.match_data[:totem]
        unless redis.exists "totem/#{totem}"
          response.reply %{Error: there is no totem "#{totem}".}
          return
        end

        past_owning_user_id = redis.get("totem/#{totem}/owning_user_id")
        if past_owning_user_id.nil?
          response.reply %{Error: Nobody owns totem "#{totem}" so you can't kick someone from it.}
          return
        end

        redis.srem("user/#{past_owning_user_id}/totems", totem)
        redis.hdel("totem/#{totem}/waiting_since", past_owning_user_id)
        redis.hdel("totem/#{totem}/message", past_owning_user_id)
        robot.send_messages(Lita::Source.new(user: Lita::User.find_by_id(past_owning_user_id)), %{You have been kicked from totem "#{totem}" by #{response.user.name}.})
        next_user_id = redis.lpop("totem/#{totem}/list")
        if next_user_id
          redis.set("totem/#{totem}/owning_user_id", next_user_id)
          redis.sadd("user/#{next_user_id}/totems", totem)
          redis.hset("totem/#{totem}/waiting_since", next_user_id, Time.now.to_i)
          robot.send_messages(Lita::Source.new(user: Lita::User.find_by_id(next_user_id)), %{You are now in possession of totem "#{totem}".})
        else
          redis.del("totem/#{totem}/owning_user_id")
        end

      end

      def info(response)
        totem_param = response.match_data[:totem]
        resp        = unless totem_param.nil? || totem_param.empty?
                          channel = @@EnvironmentToSlackChannelMap[totem_param.to_sym]
                          r = "*#{totem_param}*"
                          r += " *(#{channel})*" if !channel.nil?
                          r += list_users_print(totem_param)
                          r
                      else
                        users_cache = new_users_cache
                        r           = "Totems:\n"
                        redis.smembers("totems").each do |totem|
                          channel = @@EnvironmentToSlackChannelMap[totem.to_sym]
                          r += "*#{totem}*"
                          r += " *(#{channel})*" if !channel.nil?
                          r += list_users_print(totem, '  ', users_cache)
                          r += "\n----------\n"
                        end
                        r
                      end
        response.reply resp
      end

      def stats(response)
        response.reply %{#{Stats.signalfx_dashboard}}
      end

      private
      def new_users_cache
        Hash.new { |h, id| h[id] = Lita::User.find_by_id(id) }
      end

      def list_users_print(totem, prefix='', users_cache=new_users_cache)
        str      = ''
        first_id = redis.get("totem/#{totem}/owning_user_id")
        if first_id
          waiting_since_hash = redis.hgetall("totem/#{totem}/waiting_since")
          message_hash = redis.hgetall("totem/#{totem}/message")
          timeout_hash = redis.hgetall("totem/#{totem}/timeout")
          str += "\n"
          str += "#{prefix}1. #{users_cache[first_id].name} (held for #{waiting_duration(waiting_since_hash[first_id])})"
          str += " - #{message_hash[first_id]}" if message_hash[first_id]
          str += " - timeout: #{timeout_hash[first_id]}" if timeout_hash[first_id]
          rest = redis.lrange("totem/#{totem}/list", 0, -1)
          rest.each_with_index do |user_id, index|
            str += "\n"
            str += "#{prefix}#{index+2}. #{users_cache[user_id].name} (waiting for #{waiting_duration(waiting_since_hash[user_id])})"
            str += " - #{message_hash[user_id]}" if message_hash[user_id]
            str += " - timeout: #{timeout_hash[user_id]}" if timeout_hash[user_id]
          end
        else
          str += " *- Available*"
        end
        str
      end

      def waiting_duration(time)
        ChronicDuration.output(Time.now.to_i - time.to_i, format: :short) || "0s"
      end

      def take_totem(response, totem, user_id, timeout)
        redis.set("totem/#{totem}/owning_user_id", user_id)
        redis.sadd("user/#{user_id}/totems", totem)
        redis.hset("totem/#{totem}/waiting_since", user_id, Time.now.to_i)
        if @@DemoEnvironments.include? totem
          # Create async job
          after(timeout*3600) do |timer|
            # Check that the user is the current owner of the totem
            current_owner = redis.get("totem/#{totem}/owning_user_id")
            if user_id == current_owner
              yield_totem(response.match_data[:totem], user_id, response, true)
            end
          end
        end
      end

      def get_user_by_id(user_id)
        # This query by user_id is needed because if we take the user
        # from the response, then it will always be the user that first timed out
        Lita::User.find_by_id(user_id)
      end

      def yield_totem(totem, user_id, response, timeout=false)
        waiting_since_hash = redis.hgetall("totem/#{totem}/waiting_since")
        Stats.capture_holding_time(totem, waiting_since_hash[user_id])    

        redis.srem("user/#{user_id}/totems", totem)
        redis.hdel("totem/#{totem}/waiting_since", user_id)
        redis.hdel("totem/#{totem}/message", user_id)
        redis.hdel("totem/#{totem}/timeout", user_id)
        redis.srem("user/#{user_id}/totems/reminder", totem) if redis.smembers("user/#{user_id}/totems/reminder").include?(totem)
        next_user_id = redis.lpop("totem/#{totem}/list")
        # TODO: Remove async job
        # TODO: Find a way to identify pending jobs so we can cancel them instead of letting them finish and then checking 
        if next_user_id
          timeout_hash = redis.hgetall("totem/#{totem}/timeout")
          Stats.capture_waiting_time(totem, waiting_since_hash[next_user_id])
          take_totem(response, totem, next_user_id, timeout_hash[next_user_id].to_i)
          next_user = Lita::User.find_by_id(next_user_id)
          queue_size = redis.llen("totem/#{totem}/list")
          robot.send_messages(Lita::Source.new(user: next_user), %{You are now in possession of totem "#{totem}", yielded by #{response.user.name}. There are #{queue_size} people in line after you.})
          if timeout
            robot.send_messages(Lita::Source.new(user: get_user_by_id(user_id)), %{Your totem "#{totem}", expired and has been given to #{next_user.name}.})
          else
            response.reply "You have yielded the totem to #{next_user.name}."
          end
        else
          redis.del("totem/#{totem}/owning_user_id")
          if timeout
            robot.send_messages(Lita::Source.new(user: get_user_by_id(user_id)), %{Your totem "#{totem}" has expired.})
          else
            response.reply %{You have yielded the "#{totem}" totem.}
          end
        end
      end

      def queued_by_user(user_id)
        redis.smembers("totems").select do |totem|
          # there's no easy way to check membership in a list in redis
          # right now let's iterate through the list, but to make this
          # more performant we could convert these lists to sorted sets
          redis.lrange("totem/#{totem}/list", 0, -1).include?(user_id)
        end
      end
    end

    Lita.register_handler(Totems)
  end
end
