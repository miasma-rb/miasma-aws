require 'miasma'

module Miasma
  module Contrib
    module Aws
      module Api
        autoload :Sts, 'miasma-aws/api/sts'
        autoload :Iam, 'miasma-aws/api/iam'
      end
    end
  end
end
