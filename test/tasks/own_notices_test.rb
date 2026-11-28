# frozen_string_literal: true

require "test_helper"
require_relative "../../tasks/own_notices"

# tasks/own_notices.rb: a license notice in a package's source file is the
# package's own when the license it states is one the package's
# package.json declares and every copyright holder it names is one the
# package's license files name. Anything else in a source file is the
# notice of another work.
class OwnNoticesTest < Minitest::Test
  MIT_FILE = "The MIT License (MIT)\n\nCopyright (c) 2017 David Sherret\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\n"
  MIT_NOTICE = "Permission is hereby granted, free of charge, to any person obtaining a copy of this software\n"

  def test_covers_a_notice_that_states_the_license_the_package_declares_and_the_holder_its_license_file_names
    assert_covers credit("MIT", MIT_FILE), "// Copyright (c) 2017 David Sherret\n// #{MIT_NOTICE}"
  end

  def test_takes_a_holder_the_same_whatever_its_years_case_punctuation_or_copyright_sign
    credit = credit("MIT", "Copyright (c) 2017-2020 David Sherret, All rights reserved.\n")

    assert_covers credit, "/*\n * Copyright © 2021 david sherret\n * #{MIT_NOTICE} */\n"
    assert_covers credit, "Copyright 2022, 2023 David  Sherret\n#{MIT_NOTICE}"
  end

  def test_leaves_a_notice_of_the_same_license_with_another_holder_to_the_works_the_build_knows
    refute_covers credit("MIT", MIT_FILE), "// Copyright (c) 2019 Julian Gruber\n// #{MIT_NOTICE}"
  end

  def test_leaves_a_notice_of_the_same_holder_in_another_license_to_the_works_the_build_knows
    refute_covers credit("MIT", MIT_FILE), "// Copyright (c) 2017 David Sherret\n// Licensed under the Apache License, Version 2.0\n"
    refute_covers credit("MIT", MIT_FILE), "// Copyright (c) 2017 David Sherret\n// Permission to use, copy, modify, and/or distribute this software for any\n"
  end

  def test_leaves_a_notice_that_names_no_holder_to_the_works_the_build_knows
    refute_covers credit("MIT", MIT_FILE), "// #{MIT_NOTICE}"
    refute_covers credit("MIT", MIT_FILE), "// Copyright (c) 2017\n// #{MIT_NOTICE}"
  end

  def test_covers_a_file_only_when_every_holder_and_every_license_in_it_is_credited
    refute_covers credit("MIT", MIT_FILE), "// Copyright (c) 2017 David Sherret\n// Copyright (c) 2019 Julian Gruber\n// #{MIT_NOTICE}"
    refute_covers credit("MIT", MIT_FILE), "// Copyright (c) 2017 David Sherret\n// #{MIT_NOTICE}// Redistribution and use in source and binary forms\n"
  end

  def test_leaves_a_notice_whose_phrase_does_not_say_which_license_it_is_to_the_works_the_build_knows
    refute_covers credit("MIT", MIT_FILE), "// Copyright (c) 2017 David Sherret\n// Licensed under the MIT License\n"
  end

  def test_covers_the_notices_of_each_license_in_an_expression_the_package_declares
    credit = credit("(MIT OR Apache-2.0)", MIT_FILE)

    assert_covers credit, "// Copyright (c) 2017 David Sherret\n// #{MIT_NOTICE}"
    assert_covers credit, "// Copyright (c) 2017 David Sherret\n// Licensed under the Apache License, Version 2.0\n"
    refute_covers credit, "// Copyright (c) 2017 David Sherret\n// Redistribution and use in source and binary forms\n"
  end

  def test_covers_a_notice_of_a_phrase_that_two_licenses_share_when_the_package_declares_either
    notice = "// Copyright (c) 2017 David Sherret\n// Permission to use, copy, modify, and/or distribute this software for any\n"

    assert_covers credit("ISC", MIT_FILE), notice
    assert_covers credit("0BSD", MIT_FILE), notice
    refute_covers credit("MIT", MIT_FILE), notice
  end

  def test_covers_a_license_identifier_the_package_declares_and_leaves_one_it_does_not
    credit = credit("MIT", MIT_FILE)

    assert_covers credit, tagged("MIT")
    refute_covers credit, tagged("GPL-3.0-only")
    refute_covers credit, tagged("MIT OR GPL-3.0-only")
    refute_covers credit, tagged("")
  end

  def test_covers_nothing_for_a_package_that_declares_no_license_or_whose_license_files_name_no_holder
    refute_covers credit(nil, MIT_FILE), "// Copyright (c) 2017 David Sherret\n// #{MIT_NOTICE}"
    refute_covers credit("MIT", "The MIT License\n"), "// Copyright (c) 2017 David Sherret\n// #{MIT_NOTICE}"
    refute_covers credit("MIT"), "// Copyright (c) 2017 David Sherret\n// #{MIT_NOTICE}"
  end

  def test_reads_text_that_is_not_valid_utf8_and_a_holder_with_letters_beyond_ascii
    credit = credit("MIT", "Copyright © 2020 Zoë Müller\n".b)

    assert_covers credit, "// Copyright (c) 2020 Zoë Müller \xFF\n// #{MIT_NOTICE}".b
    refute_covers credit, "// Copyright (c) 2020 Zoe Muller\n// #{MIT_NOTICE}".b
  end

  def test_marks_each_phrase_that_starts_a_license_notice
    assert_equal ["Permission is hereby granted", "Licensed under the Apache License", OwnNotices::TAG, "Licensed under the"],
      "Permission is hereby granted, Licensed under the Apache License, #{OwnNotices::TAG}: MIT, Licensed under the BSL".scan(OwnNotices::NOTICE)
  end

  private

  # A source file of the holder, with a license tag that gives +expression+.
  # The tag's name comes from the constant, so that the file has no tag of
  # its own for REUSE to read.
  def tagged(expression) = "// Copyright (c) 2017 David Sherret\n// #{OwnNotices::TAG}: #{expression}\n"

  # What the npm entry of a package that declares +license+ and has
  # license files with +texts+ credits.
  def credit(license, *texts) = OwnNotices.credit(license, texts)

  def assert_covers(credit, text) = assert(credit.covers?(text), "expected the credit to cover #{text.inspect}")

  def refute_covers(credit, text) = refute(credit.covers?(text), "expected the credit not to cover #{text.inspect}")
end
