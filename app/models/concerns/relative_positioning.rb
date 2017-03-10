module RelativePositioning
  extend ActiveSupport::Concern

  MIN_POSITION = 0
  START_POSITION = Gitlab::Database::MAX_INT_VALUE / 2
  MAX_POSITION = Gitlab::Database::MAX_INT_VALUE
  DISTANCE = 500

  included do
    after_save :save_positionable_neighbours
  end

  def max_relative_position
    self.class.in_projects(project.id).maximum(:relative_position)
  end

  def prev_relative_position
    prev_pos = nil

    if self.relative_position
      prev_pos = self.class.
        in_projects(project.id).
        where('relative_position < ?', self.relative_position).
        maximum(:relative_position)
    end

    prev_pos
  end

  def next_relative_position
    next_pos = nil

    if self.relative_position
      next_pos = self.class.
        in_projects(project.id).
        where('relative_position > ?', self.relative_position).
        minimum(:relative_position)
    end

    next_pos
  end

  def move_between(before, after)
    return move_after(before) unless after
    return move_before(after) unless before

    pos_before = before.relative_position
    pos_after = after.relative_position

    # We can't insert an issue between two other if the distance is 1 or 0
    # so we need to handle this collision properly
    if pos_after && (pos_after - pos_before).abs <= 1
      self.relative_position = pos_before
      before.move_before(self)
      after.move_after(self)

      @positionable_neighbours = [before, after]
    else
      self.relative_position = position_between(pos_before, pos_after)
    end
  end

  def move_before(after)
    self.relative_position = position_between(after.prev_relative_position, after.relative_position)
  end

  def move_after(before)
    self.relative_position = position_between(before.relative_position, before.next_relative_position)
  end

  def move_to_end
    self.relative_position = position_between(max_relative_position || START_POSITION, MAX_POSITION)
  end

  private

  # This method takes two integer values (positions) and
  # calculates the position between them. The range is huge as
  # the maximum integer value is 2147483647. We are incrementing position by 1000 every time
  # when we have enough space. If distance is less then 500 we are calculating an average number
  def position_between(pos_before, pos_after)
    pos_before ||= MIN_POSITION
    pos_after ||= MAX_POSITION

    pos_before, pos_after = [pos_before, pos_after].sort

    if pos_after - pos_before < DISTANCE * 2
      (pos_after + pos_before) / 2
    else
      if pos_before == MIN_POSITION
        pos_after - DISTANCE
      elsif pos_after == MAX_POSITION
        pos_before + DISTANCE
      else
        (pos_after + pos_before) / 2
      end
    end
  end

  def save_positionable_neighbours
    return unless @positionable_neighbours

    status = @positionable_neighbours.all?(&:save)
    @positionable_neighbours = nil

    status
  end
end
