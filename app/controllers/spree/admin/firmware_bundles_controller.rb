module Spree
  module Admin
    # The "Firmware" tab: bundles per hardware revision, newest first. Create a draft (or take one
    # CI uploaded), add images, publish, set the channel and rollout, pause (kill switch: `check`
    # stops offering it at once), resume, revoke (devices still on it are told so and offered the
    # newest good bundle). Each bundle page shows its install reports.
    class FirmwareBundlesController < Spree::Admin::BaseController
      PER_PAGE = 50
      DRAFT_FIELDS = %i[hw_rev version channel rollout_percent min_app_version security_epoch release_notes].freeze
      RELEASED_FIELDS = %i[channel rollout_percent min_app_version release_notes].freeze

      before_action :load_bundle, except: %i[index new create]

      def index
        @filters = params.permit(:hw_rev, :channel, :state).to_h.symbolize_keys
        scope = FirmwareBundle.includes(:images)
        scope = scope.where(hw_rev: @filters[:hw_rev]) if @filters[:hw_rev].present?
        scope = scope.where(channel: @filters[:channel]) if Firmware::CHANNELS.include?(@filters[:channel])
        scope = scope.where(state: @filters[:state]) if FirmwareBundle::STATES.include?(@filters[:state])
        sorted = scope.to_a.group_by(&:hw_rev).sort.flat_map { |_, list| FirmwareBundle.sort_newest_first(list) }
        @bundles = Kaminari.paginate_array(sorted)
                           .page(params[:page]).per(PER_PAGE)
        @report_counts = FirmwareReport.where(firmware_bundle_id: @bundles.map(&:id)).group(:firmware_bundle_id, :result).count
        @hw_revs = FirmwareBundle.distinct.order(:hw_rev).pluck(:hw_rev)
      end

      def new
        @bundle = FirmwareBundle.new(hw_rev: FirmwareBundle.order(:created_at).last&.hw_rev, channel: 'internal')
      end

      def create
        @bundle = FirmwareBundle.new(bundle_params(DRAFT_FIELDS).merge(state: 'draft', created_by: try_spree_current_user&.email))
        if @bundle.save
          flash[:success] = "Draft #{@bundle.label} created; add its images"
          redirect_to spree.admin_firmware_bundle_path(@bundle)
        else
          flash.now[:error] = @bundle.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      end

      def show
        @images = @bundle.images.includes(file_attachment: :blob)
        @result_counts = @bundle.reports.group(:result).count
        @stage_counts = @bundle.reports.where.not(result: 'ok').group(:component, :stage, :result).count
        @reports = @bundle.reports.newest_first.limit(50)
        @new_image = FirmwareImage.new(firmware_bundle_id: @bundle.id) if @bundle.editable?
      end

      def edit; end

      def update
        fields = @bundle.editable? ? DRAFT_FIELDS : RELEASED_FIELDS
        if @bundle.update(bundle_params(fields))
          flash[:success] = "#{@bundle.label} updated"
          redirect_to spree.admin_firmware_bundle_path(@bundle)
        else
          flash.now[:error] = @bundle.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        if @bundle.destroy
          flash[:success] = "Draft #{@bundle.label} deleted"
          redirect_to spree.admin_firmware_bundles_path
        else
          flash[:error] = @bundle.errors.full_messages.to_sentence
          redirect_to spree.admin_firmware_bundle_path(@bundle)
        end
      end

      def publish
        transition(:publish!, @bundle.paused? ? 'resumed' : 'published')
      end

      def pause
        transition(:pause!, 'paused: no device is offered it now')
      end

      def revoke
        transition(:revoke!, 'revoked')
      end

      private

      def model_class
        FirmwareBundle
      end

      def load_bundle
        @bundle = FirmwareBundle.find(params[:id])
      end

      def bundle_params(fields)
        params.require(:firmware_bundle).permit(*fields)
      end

      def transition(method, done)
        if @bundle.public_send(method)
          flash[:success] = "#{@bundle.label} #{done}"
        else
          flash[:error] = @bundle.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_firmware_bundle_path(@bundle)
      end
    end
  end
end
