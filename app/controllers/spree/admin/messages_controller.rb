module Spree
    module Admin
      class MessagesController <  Spree::Admin::BaseController
        before_action :set_msgs, only: [:index]

        def index

          session[:return_to] = request.url


          # respond_with(@msgs)
          # respond_with(html: "<div>Hey</div>")
        end
  
        def message_support
          session[:return_to] = request.url
        end


        # kludgey actions for messages by index
        def thread_list_one
          session[:return_to] = request.url
        end

        def thread_list_two
          session[:return_to] = request.url
        end

        private

        def set_msgs
          @msgs = [
            {
              id: 0,
              user: 'George Harrison',
              txt: 'Where is my CBD?'
            },
            {
              id: 1,
              user: 'John Lennon',
              txt: 'Still waiting...'
            },
            {
              id: 2,
              user: 'Paul McCartney',
              txt: 'Love me do?'
            },
            {
              id: 3,
              user: 'Ringo Starr',
              txt: 'Groovey'
            }
          ]
        end
        
      end
    end
  end