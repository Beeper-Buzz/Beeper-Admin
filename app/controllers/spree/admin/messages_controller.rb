
class Spree::Admin::MessagesController <  Spree::Admin::BaseController

	before_action :set_session

	def index
		@messages = Message.admin_conversations
	end

	def show
		@message = Message.find(params[:id])
		@messages = Message.admin_conversations
		@chat_messages = Message.find_with_sender_id(@message.sender_id)
		render :index
	end

	def create
		data = {}
		data[:body] = create_params['body']
		data[:thread_id] = create_params['thread_id']

		@message = Message.create_message_for_admin(data[:body], data[:thread_id], spree_current_user.id)

	end


	def message_support

	end


private

	def set_session
		session[:return_to] = request.url
	end

	def create_params
		params.permit( :body, :thread_id, :utf8, :authenticity_token, :commit )
	end

end
