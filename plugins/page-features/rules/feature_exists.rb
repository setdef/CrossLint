# frozen_string_literal: true

# A file is a page unless the text that {path} matched has a dot in its
# last segment: with {path}.tsx, Home.test.tsx, Home.stories.tsx, and
# Home.spec.tsx are files about a page, and with {path}.page.tsx,
# Home.page.tsx is a page and Home.test.page.tsx isn't. A page pattern
# with no {path} takes every file it matches.
class FeatureExists < CrossLint::Rule
  def check(artifact)
    return [] if File.basename(artifact.match.fetch("path", "")).include?(".")

    feature = artifact.piece("feature")
    return [] if feature.exist?

    [violation(artifact, "no feature file at #{feature.path}")]
  end
end
