require 'miasma'

module Miasma
  module Contrib
    module Aws
      # AWS API helpers
      module Api
        autoload :Sts, 'miasma-aws/api/sts'
        autoload :Iam, 'miasma-aws/api/iam'
      end
    end
  end
end
