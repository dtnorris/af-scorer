# frozen_string_literal: true

module AFScoring
  module NosTwoStageRunnerFactory
    def new(*args, **kwargs, &block)
      if self == Runner && NosTwoStage.enabled?
        return NosTwoStageRunner.new(*args, **kwargs, &block)
      end

      super
    end
  end

  Runner.singleton_class.prepend(NosTwoStageRunnerFactory)
end
