require 'sidekiq'
module Lita
    module Handlers
        class Timeout
            include Sidekiq::Job

            def perform()
                sleep 10
                puts "Workin' test"
            end
        end
    end
end
