module Spree
  module Admin
    # CMS sections for the storefront's pages (homepage, /creators, ...). The
    # index shows one page at a time, picked by `page_key`.
    class HomepageSectionsController < Spree::Admin::BaseController
      before_action :set_homepage_section, only: [:edit, :update, :destroy, :show]
      before_action :set_page_key, only: [:index, :new]

      def index
        @q = HomepageSection.for_page(@page_key).ransack(params[:q])
        @collection = @q.result
                        .ordered
                        .page(params[:page])
                        .per(params[:per_page] || 25)
        @min_position = HomepageSection.for_page(@page_key).minimum(:position) || 0
        @max_position = HomepageSection.for_page(@page_key).maximum(:position) || 0
      end

      def new
        @homepage_section = HomepageSection.new(page_key: @page_key)
      end

      def create
        @homepage_section = HomepageSection.new(homepage_section_params)

        respond_to do |format|
          if @homepage_section.save
            flash[:success] = Spree.t('homepage_section.added_success')
            format.html { redirect_to page_sections_path(@homepage_section) }
            format.json { render json: @homepage_section, status: :created }
          else
            flash[:error] = @homepage_section.errors.full_messages.join(', ')
            format.html { render :new }
            format.json { render json: @homepage_section.errors, status: :unprocessable_entity }
          end
        end
      end

      def edit
      end

      def show
      end

      def update
        respond_to do |format|
          if @homepage_section.update(homepage_section_params)
            flash[:success] = Spree.t('homepage_section.update_success')
            format.html { redirect_to page_sections_path(@homepage_section) }
            format.json { render json: @homepage_section }
          else
            flash[:error] = @homepage_section.errors.full_messages.join(', ')
            format.html { render :edit }
            format.json { render json: @homepage_section.errors, status: :unprocessable_entity }
          end
        end
      end

      def destroy
        if @homepage_section.destroy
          flash[:success] = Spree.t('homepage_section.deleted_success')
        else
          flash[:error] = Spree.t('homepage_section.delete_failed')
        end
        redirect_to page_sections_path(@homepage_section)
      end

      # Move section up in order (within its page)
      def move_up
        @homepage_section = HomepageSection.find(params[:id])
        swap_with(@homepage_section.previous_on_page, 'up')
        redirect_to page_sections_path(@homepage_section)
      end

      # Move section down in order (within its page)
      def move_down
        @homepage_section = HomepageSection.find(params[:id])
        swap_with(@homepage_section.next_on_page, 'down')
        redirect_to page_sections_path(@homepage_section)
      end

      # Toggle visibility
      def toggle_visibility
        @homepage_section = HomepageSection.find(params[:id])
        @homepage_section.update(is_visible: !@homepage_section.is_visible)

        status = @homepage_section.is_visible ? 'visible' : 'hidden'
        flash[:success] = "Section is now #{status}"

        redirect_to page_sections_path(@homepage_section)
      end

      private

      def swap_with(other, direction)
        unless other
          flash[:error] = "Cannot move section #{direction}"
          return
        end

        ActiveRecord::Base.transaction do
          current_pos = @homepage_section.position
          @homepage_section.update_attribute(:position, other.position)
          other.update_attribute(:position, current_pos)
        end
        flash[:success] = "Section moved #{direction} successfully"
      end

      def page_sections_path(section)
        admin_homepage_sections_path(page_key: section.page_key)
      end

      def set_page_key
        key = params[:page_key].to_s
        @page_key = HomepageSection::PAGES.include?(key) ? key : HomepageSection::DEFAULT_PAGE
      end

      def set_homepage_section
        @homepage_section = HomepageSection.find(params[:id])
      end

      def homepage_section_params
        params.require(:homepage_section).permit(
          :title,
          :section_type,
          :content,
          :position,
          :is_visible,
          :settings,
          :page_key
        )
      end
    end
  end
end
