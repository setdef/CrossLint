# frozen_string_literal: true

# A page's file has one suffix, as in Home.tsx. A file whose name has a
# second, as in Home.test.tsx, Home.stories.tsx, or Home.spec.tsx, is a
# test, a story, or another file about a page, whatever the page setting
# matched it with.
class FeatureExists < CrossLint::Rule
  def check(artifact)
    return [] if File.basename(artifact.path, ".*").include?(".")

    feature = artifact.companion("feature")
    return [] if feature.exist?

    [violation(artifact, "no feature file at #{feature.path}")]
  end
end
