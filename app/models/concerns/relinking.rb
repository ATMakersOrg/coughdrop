module Relinking
  extend ActiveSupport::Concern
  
  def links_to?(board, skip_disabled_links=false)
    (self.buttons || []).each do |button|
      if button['load_board'] && button['load_board']['id'] == board.global_id
        if skip_disabled_links
          return !button['hidden'] && !button['link_disabled']
        else
          return true
        end
      end
    end
    false
  end
  
  def for_user?(user)
    user && self.user_id == user.id
  end
  
  def just_for_user?(user)
    return !self.public && self.for_user?(user) && !self.shared_by?(user)
  end
  
  def copy_for(user, opts=nil)
    opts ||= {}
    make_public = opts[:make_public] || false
    copy_id = opts[:copy_id]
    prefix = opts[:prefix]
    new_owner = opts[:new_owner] || false
    disconnect = opts[:disconnect] || false
    copier = opts[:copier]

    raise "missing user" unless user
    if !self.board_content_id || self.board_content_id == 0
      BoardContent.generate_from(self)
    end
    if self.settings['protected'] && self.settings['protected']['vocabulary']
      if !self.copyable_if_authorized?(self.user)
        # If the board author isn't allowed to create a copy, then
        # don't allow it in a batch
        raise "not authorized to copy #{self.global_id} by #{self.user.global_id}"
      end
    end
    board = Board.new(:user_id => user.id, :parent_board_id => self.id)
    board.key = board.generate_board_key(self.key.split(/\//)[1])
    disconnected = false
    if disconnect && copier && self.allows?(copier, 'edit')
      board.settings['copy_parent_board_id'] = self.global_id
      board.parent_board_id = nil
      disconnected = true
    end
    board.settings['copy_id'] = copy_id
    board.settings['source_board_id'] = self.source_board.global_id
    board.settings['name'] = self.settings['name']
    if !prefix.blank? && board.settings['name']
      if self.settings['prefix'] && board.settings['name'].index(self.settings['prefix']) == 0
        board.settings['name'] = board.settings['name'].sub(/#{self.settings['prefix']}\s+/, '')
      end
      if !board.settings['name'].index(prefix) != 0
        board.settings['name'] = "#{prefix} #{board.settings['name']}"
      end
      board.settings['prefix'] = prefix
    end
    board.settings['description'] = self.settings['description']
    board.settings['protected'] = self.settings['protected']
    if board.settings['protected'] && board.settings['protected']['vocabulary']
      if new_owner && self.allows?(copier, 'edit') && !self.settings['protected']['sub_owner']
        # copyable_if_authorized is already checked above
        # also ensure that new_owners can't create more new_owners
        board.settings['protected']['vocabulary_owner_id'] = user.global_id
        board.settings['protected']['sub_owner'] = self.settings['protected']['sub_owner'] || self.user.global_id != user.global_id
        board.settings['protected']['sub_owner'] = false if disconnected
      else
        board.settings['protected']['vocabulary_owner_id'] = self.settings['protected']['vocabulary_owner_id'] || self.user.global_id
        board.settings['protected']['sub_owner'] = self.settings['protected']['sub_owner'] || self.user.global_id != user.global_id
      end
    end
    board.settings['image_url'] = self.settings['image_url']
    board.settings['locale'] = self.settings['locale']
    board.settings['locales'] = self.settings['locales']
    board.settings['translations'] = BoardContent.load_content(self, 'translations')
    board.settings['background'] = BoardContent.load_content(self, 'background')
    board.settings['buttons'] = self.buttons
    board.settings['grid'] = BoardContent.load_content(self, 'grid')
    board.settings['intro'] = BoardContent.load_content(self, 'intro')
    board.settings['downstream_board_ids'] = self.settings['downstream_board_ids']
    board.settings['common_library'] = self.settings['common_library'] if self.settings['common_library']
    board.settings['swapped_library'] = self.settings['swapped_library'] if self.settings['swapped_library']
    board.settings['word_suggestions'] = self.settings['word_suggestions']
    board.settings['categories'] = self.settings['categories']
    board.settings['license'] = self.settings['license']
    board.settings['intro']['unapproved'] = true if board.settings['intro']
    board.settings['never_edited'] = true
    board.public = true if make_public
    board.settings.delete('unlisted') if make_public
    BoardContent.apply_clone(self, board) if self.board_content_id && self.board_content_id != 0
    # board.map_images has to create a record for each image in the
    # board, and while that is useful for tracking, it's actually redundant
    # so we can postpone it and save some time for batch copies
    board.instance_variable_set('@map_later', true)
    board.save!
    if !user.instance_variable_get('@already_updating_available_boards')
      user.update_available_boards
    end
    # puts "  done COPYING #{self.global_id}"
    board
  end
  
  # If copy_id = nil, this is an original, root board
  # If copy_id == self.global_id, this is a root board
  # If copy_id != self.global_id, this is a sub-board of Board.find_by_global_id(copy_id)
  def assert_copy_id
    return true if self.settings['copy_id']
    return false if !self.parent_board_id
    if (self.settings['immediately_upstream_board_ids'] || []).length > 0
      upstreams = Board.find_all_by_global_id(self.settings['immediately_upstream_board_ids'])
      # if all upstream boards are copies and belong to the current user, let's assume this goes with them
      if upstreams.all?{|u| u.parent_board_id } && upstreams.map(&:user_id).uniq == [self.user_id]
        parent = self.parent_board
        upstream_parents = upstreams.map(&:parent_board).select{|b| b.user_id == parent.user_id }
        # if any original upstream boards belong to the current board's original user, then this is
        # probably part of a copy group
        if upstream_parents.map(&:user_id).uniq == [parent.user_id]
          asserted_copy_id = upstreams.map{|u| u.settings['asserted_copy_id'] && u.settings['copy_id'] }.compact.first
          # if a known root board is found, go ahead and mark it as such
          if upstreams.length > 10 && self.key.match(/top-page/)
            self.settings['copy_id'] = self.global_id
            self.settings['asserted_copy_id'] = true
            self.save
            return true
          # if any of the upstream boards have an asserted copy id, go ahead and use that
          elsif asserted_copy_id
            self.settings['copy_id'] = asserted_copy_id
            self.settings['asserted_copy_id'] = true
            self.save
            return true
          # if the board and its upstreams were all created within 30 seconds of each other, call it a batch
          elsif self.created_at - (upstreams.map(&:created_at).min) < 30
            self.settings['copy_id'] = upstreams[0].global_id
            self.settings['asserted_copy_id'] = true
            self.save
            return true
          # if the upstream boards have unasserted copy ids, let's not link it up
          elsif upstreams.any?{|u| u.settings['copy_id'] }
          # if the parent has no upstream boards, consider it the root of the copy group
          elsif upstreams.length == 1 && (upstreams[0].settings['immediately_upstream_board_ids'] || []).length == 0
            self.settings['copy_id'] = upstreams[0].global_id
            self.settings['asserted_copy_id'] = true
            self.save
            return true
          end
        end
      end
    end
    return false
  end
  
  def replace_links!(old_board, new_board)
    buttons = self.buttons
    buttons.each_with_index do |button, idx|
      if button['load_board'] && button['load_board']['id'] == old_board.global_id
        button['load_board']['id'] = new_board.global_id
        button['load_board']['key'] = new_board.key
      end
    end
    self.settings['buttons'] = buttons
    self.settings['downstream_board_ids'] = (self.settings['downstream_board_ids'] || []).map{|id| id == old_board.global_id ? new_board.global_id : id }
  end

  def slice_locales(locales_to_keep, ids_to_update=[], updater=nil)
    updater = User.find_by_path(updater) if updater.is_a?(String)
    return {sliced: false, reason: 'id not included'} unless ids_to_update.include?(self.global_id)
    all_locales = [self.settings['locale']]
    trans = BoardContent.load_content(self, 'translations') || {}
    trans.each do |key, hash|
      next unless hash.is_a?(Hash)
      all_locales += hash.keys
    end
    all_locales.uniq!
    board_locales_to_keep = locales_to_keep & all_locales
    return {sliced: false, reason: 'no locales would be kept'} if board_locales_to_keep.length == 0
    return {sliced: true, ids: [self.global_id], reason: 'already includes only specified locales'} if locales_to_keep.sort == all_locales.sort && ids_to_update == [self.global_id]
    if !board_locales_to_keep.include?(self.settings['locale'])
      self.update_default_locale!(self.settings['locale'], board_locales_to_keep[0])
    end
    trans = self.settings['translations'] || trans
    trans.each do |key, hash|
      if hash.is_a?(Hash)
        trans[key] = hash.slice(*board_locales_to_keep)
      end
    end
    self.settings['translations'] = trans
    self.instance_variable_set('@map_later', true)
    self.save!
    sliced_ids = [self.global_id]
    if ids_to_update.length > 1
      board_ids = ids_to_update & (self.settings['downstream_board_ids'] || [])
      Board.find_batches_by_global_id(board_ids) do |board|
        next unless board.allows?(updater, 'edit')
        res = board.slice_locales(locales_to_keep, [board.global_id], updater)
        sliced_ids << board.global_id if res[:sliced]
      end
    end
    return {sliced: true, ids: sliced_ids}
  end

  def update_default_locale!(old_default_locale, new_default_locale)
    if new_default_locale && self.settings['locale'] == old_default_locale && old_default_locale != new_default_locale
      buttons = self.buttons
      trans = BoardContent.load_content(self, 'translations') || {}
      anything_translated = false
      trans['board_name'] ||= {}
      trans['board_name'][old_default_locale] ||= self.settings['name']
      if trans['board_name'][new_default_locale]
        self.settings['name'] = trans['board_name'][new_default_locale]
        anything_translated = true
      end
      buttons.each do |btn|
        btn_trans = trans[btn['id'].to_s] || {}
        btn_trans[old_default_locale] ||= {}
        if !btn_trans[old_default_locale]['label']
          btn_trans[old_default_locale]['label'] = btn['label']
          btn_trans[old_default_locale]['vocalization'] = btn['vocalization']
          btn_trans[old_default_locale].delete('vocalization') if !btn_trans[old_default_locale]['vocalization']
          btn_trans[old_default_locale]['inflections'] = btn['inflections']
          btn_trans[old_default_locale].delete('inflections') if !btn_trans[old_default_locale]['inflections']
        end
        if btn_trans[new_default_locale]
          anything_translated = true
          btn['label'] = btn_trans[new_default_locale]['label']
          btn['vocalization'] = btn_trans[new_default_locale]['vocalization']
          btn.delete('vocalization') if !btn['vocalization']
          btn['inflections'] = btn_trans[new_default_locale]['inflections']
          btn.delete('inflections') if !btn['inflections']
        end
        trans[btn['id'].to_s] = btn_trans
      end
      trans['default'] = new_default_locale
      trans['current_label'] = new_default_locale
      trans['current_vocalization'] = new_default_locale
      self.settings['translations'] = trans

      if anything_translated
        self.settings['buttons'] = buttons
        self.settings['locale'] = new_default_locale
      end
    end
  end

  module ClassMethods
    # take the previous board set in its entirety,
    # and, depending on the preference, make new copies
    # of sub-boards, or use existing copies of sub-boards
    # for specified boards (all if none specified)
    # on behalf of the specified used
    def replace_board_for(user, opts)
      auth_user = opts[:authorized_user]
      starting_old_board = opts[:starting_old_board] || raise("starting_old_board required")
      starting_new_board = opts[:starting_new_board] || raise("starting_new_board required")
      update_inline = opts[:update_inline] || false
      make_public = opts[:make_public] || false
      board_ids = []
      # get all boards currently connected to the user
      if user.settings['preferences'] && user.settings['preferences']['home_board']
        board_ids += [user.settings['preferences']['home_board']['id']] 
        board = Board.find_by_path(user.settings['preferences']['home_board']['id'])
        board.track_downstream_boards!
        downstream_ids = board.settings['downstream_board_ids']
        if opts[:valid_ids]
          downstream_ids = downstream_ids & opts[:valid_ids]
        end
        board_ids += downstream_ids
      end
      # include sidebar boards in the list of all user boards
      sidebar_ids = {}
      sidebar = user.sidebar_boards
      user.sidebar_boards.each do |brd|
        next unless brd['key']
        board = Board.find_by_path(brd['key'])
        next unless board
        sidebar_ids[brd['key']] = board.global_id
        board_ids += [board.global_id]
        board.track_downstream_boards!
        downstream_ids = board.settings['downstream_board_ids']
        if opts[:valid_ids]
          downstream_ids = downstream_ids & opts[:valid_ids]
        end
        board_ids += downstream_ids
      end

      boards = Board.find_all_by_path(board_ids)
      pending_replacements = [[starting_old_board, starting_new_board]]

      # we will need to update user preferences 
      # if the home board or sidebar changed
      user_home_changed = relink_board_for(user, {
        :boards => boards, 
        :copy_id => starting_new_board.global_id, 
        :old_default_locale => opts[:old_default_locale],
        :new_default_locale => opts[:new_default_locale],
        :pending_replacements => pending_replacements, 
        :copy_prefix => opts[:copy_prefix],
        :update_preference => (update_inline ? 'update_inline' : nil), 
        :make_public => make_public, 
        :new_owner => opts[:new_owner],
        :disconnect => opts[:disconnect],
        :authorized_user => auth_user
      })
      sidebar_changed = false
      sidebar_ids.each do |key, id|
        if @replacement_map && @replacement_map[id]
          idx = sidebar.index{|s| s['key'] == key }
          board = @replacement_map[id]
          sidebar[idx]['key'] = board.key
          sidebar_changed = true
        end
      end
      
      # if the user's home board was replaced, update their preferences
      if user_home_changed || sidebar_changed
        if user_home_changed
          new_home = user_home_changed
          user.update_setting({
            'preferences' => {'home_board' => {
              'id' => new_home.global_id,
              'key' => new_home.key
            }}
          })
        end
        if sidebar_changed
          user.settings['preferences']['sidebar_boards'] = sidebar
          user.save
        end
      elsif user.settings['preferences']['home_board']
        home = Board.find_by_path(user.settings['preferences']['home_board']['id'])
        home.track_downstream_boards!
      end
      true
    end

    # Creates copies of specified boards 
    # (all if none specified) for the user, 
    # then wires up all the new copies to link to
    # each other instead of the originals
    def copy_board_links_for(user, opts)
      auth_user = opts[:authorized_user]
      starting_old_board = opts[:starting_old_board] || raise("starting_old_board required")
      starting_new_board = opts[:starting_new_board] || raise("starting_new_board required")
      make_public = opts[:make_public] || false
      board_ids = starting_old_board.settings['downstream_board_ids'] || []
      if opts[:valid_ids]
        board_ids = board_ids & opts[:valid_ids]
      end
      boards = Board.find_all_by_path(board_ids)
      pending_replacements = [[starting_old_board, starting_new_board]]
      # puts "starting copies"
      user.instance_variable_set('@already_updating_available_boards', true)
      boards.each do |orig|
        if !orig.allows?(user, 'view') && !orig.allows?(auth_user, 'view')
          # TODO: make a note somewhere that a change should have happened but didn't due to permissions
        else
          copy = orig.copy_for(user, make_public: make_public, copy_id: starting_new_board.global_id, prefix: opts[:copy_prefix], new_owner: opts[:new_owner], disconnect: opts[:disconnect], copier: opts[:copier])
          copy.update_default_locale!(opts[:old_default_locale], opts[:new_default_locale])
          pending_replacements << [orig, copy]
        end
      end
      user.instance_variable_set('@already_updating_available_boards', false)
      boards = [starting_old_board] + boards
      # puts "done with copies"

      relink_board_for(user, {
        :boards => boards, 
        :copy_id => starting_new_board.global_id, 
        :pending_replacements => pending_replacements, 
        :update_preference => 'update_inline', 
        :make_public => make_public, 
        :copy_prefix => opts[:copy_prefix],
        :new_owner => opts[:new_owner],
        :disconnect => opts[:disconnect],
        :authorized_user => auth_user,
        :old_default_locale => opts[:old_default_locale],
        :new_default_locale => opts[:new_default_locale]
      })
      user.update_available_boards
      # puts "done with relinking"
      @replacement_map
    end
    
    def relink_board_for(user, opts)
      auth_user = opts[:authorized_user]
      boards = opts[:boards] || raise("boards required")
      pending_replacements = opts[:pending_replacements] || raise("pending_replacements required")
      update_preference = opts[:update_preference]
      # maintain mapping of old boards to their replacements
      replacement_map = {}
      pending_replacements.each do |old_board, new_board|
        replacement_map[old_board.global_id] = new_board
      end
      # for each board that needs replacing...
      boards_to_save = []
      user.instance_variable_set('@already_updating_available_boards', true)
      while pending_replacements.length > 0
        old_board, new_board = pending_replacements.shift
        # iterate through all the original boards and look for references to the old board
        boards.each do |orig|
          board = replacement_map[orig.global_id] || orig
          # find all boards in the user's set that point to old_board_id
          if board.links_to?(old_board)
            if !board.allows?(user, 'view') && !board.allows?(auth_user, 'view')
              # TODO: make a note somewhere that a change should have happened but didn't due to permissions
            elsif update_preference == 'update_inline' && board.allows?(user, 'edit')
              # if you explicitly said update instead of replace my boards, then go ahead
              # and update in-place.
              board.replace_links!(old_board, new_board)
              boards_to_save << board
            elsif !board.just_for_user?(user)
              # if it's not already private for the user, make a private copy for the user 
              # and add to list of replacements to handle.
              copy = board.copy_for(user, make_public: opts[:make_public], copy_id: opts[:copy_id], prefix: opts[:copy_prefix], new_owner: opts[:new_owner], disconnect: opts[:disconnect], copier: opts[:copier])
              copy.replace_links!(old_board, new_board)
              boards_to_save << copy
              replacement_map[board.global_id] = copy
              pending_replacements << [board, copy]
            else
              # if it's private for the user, and no one else is using it, go ahead and
              # update it in-place
              board.replace_links!(old_board, new_board)
              boards_to_save << board
            end
          else
          end
        end
      end
      user.instance_variable_set('@already_updating_available_boards', false)
      user.update_available_boards
      boards_to_save.uniq.each do |brd|
        brd.update_default_locale!(opts[:old_default_locale], opts[:new_default_locale])
        brd.save
      end
      @replacement_map = replacement_map
      
      return replacement_map[user.settings['preferences']['home_board']['id']] if user.settings['preferences'] && user.settings['preferences']['home_board']
    end

    def cluster_related_boards(user)
      # Tries to cluster legacy boards for a user which never got clustered (copy_id) correctly
      boards = Board.where(user: user); boards.count
      roots = boards.where(['search_string ILIKE ?', "%root%"]).select{|b| !Board.find_all_by_global_id(b.settings['immediately_upstream_board_ids'] || []).detect{|b| b.user_id == user.id } }
      counts = {}
      roots.each do |board|
        (board.settings['downstream_board_ids'] || []).each do |board_id|
          counts[board_id] ||= 0
          counts[board_id] += 1
        end
      end
      unique_ids = counts.to_a.select{|id, cnt| cnt == 1 }.map(&:first)
      boards.find_in_batches(batch_size: 25) do |batch|
        batch.each do |sub_board|
          roots.each do |board|
            if !sub_board.settings['copy_id'] && (board.settings['downstream_board_ids'] || []).include?(sub_board.global_id) && unique_ids.include?(sub_board.global_id)
              sub_board.settings['copy_id'] = board.global_id
              sub_board.save
            end
          end
          if !sub_board.settings['copy_id'] && (sub_board.settings['immediately_upstream_board_ids'] || []).length == 1
            parent = Board.find_by_global_id(sub_board.settings['immediately_upstream_board_ids'])[0]
            if parent.user_id == sub_board.user_id && parent.settings['copy_id']
              sub_board.settings['copy_id'] = parent.settings['copy_id']
              sub_board.save
            end
          end
        end
      end
    end
  end
end