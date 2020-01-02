require "minitest/autorun"
require "assert_scanner"

$v = true # enables "redundant message" phase

class TestAssertScanner < Minitest::Test
  def self.todo msg
    define_method "test_#{msg}" do
      skip "not yet"
    end
  end

  def test_sanity
    ruby = %(assert [1, 2, 3].include?(b) == true, "is b in 1..3?")
    sexp = RubyParser.new.process ruby
    scan = AssertScanner.new

    scan.analyze_assert sexp

    exp = {
      s(:call, nil, :assert,
        s(:call,
          s(:call, s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3)), :include?,
            s(:call, nil, :b)),
          :==,
          s(:true))) => "redundant message?",
      s(:call, nil, :assert_equal,
        s(:call, s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3)), :include?,
          s(:call, nil, :b)),
        s(:true)) => "assert_equal exp, act",
      s(:call, nil, :assert_equal,
        s(:true),
        s(:call, s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3)), :include?,
          s(:call, nil, :b))) => "assert_equal exp, act",
      s(:call, nil, :assert_operator,
        s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3)),
        s(:lit, :include?),
        s(:call, nil, :b)) => "assert_operator obj, msg, arg",
      s(:call, nil, :assert_includes,
        s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3)),
        s(:call, nil, :b)) => "assert_includes enum, val",
    }

    assert_equal exp, scan.io

    exp = [
      #  assert([1, 2, 3].include?(b) == true, "is b in 1..3?") # original
      "  assert(([1, 2, 3].include?(b) == true))   # redundant message?",
      "  assert_equal([1, 2, 3].include?(b), true) # assert_equal exp, act",
      "  assert_equal(true, [1, 2, 3].include?(b)) # assert_equal exp, act",
      "  assert_operator([1, 2, 3], :include?, b)  # assert_operator obj, msg, arg",
      "  assert_includes([1, 2, 3], b)             # assert_includes enum, val",
    ]

    assert_equal exp, scan.out
  end

  def assert_re scanner, msg, from, to
    pattern = AssertScanner.const_get scanner
    scan = AssertScanner.new
    proc = AssertScanner.assertions[pattern]

    scan.instance_exec from, &proc

    assert_operator pattern, :===, from
    assert_match pattern, from

    exp = {to => msg}

    assert_equal exp, scan.io
  end

  def assert_re_done scanner, from
    pattern = AssertScanner.const_get scanner
    scan = AssertScanner.new
    proc = AssertScanner.assertions[pattern]

    scan.instance_exec from, &proc

    assert_operator pattern, :===, from
    assert_match pattern, from

    assert_empty scan.io
  end

  def c(msg, *args); s(:call, nil, msg, *args); end
  def a(*args);  c(:assert, *args);             end
  def r(*args);  c(:refute, *args);             end
  def ae(*args); c(:assert_equal, *args);       end
  def ai(*args); c(:assert_includes, *args);    end
  def e_(l,m,*r); s(:call, c(:_, l), m, *r);    end
  def eq(l,r);   e_(l, :must_equal,    r);      end
  def ee(l,r);   e_(l, :must_be_empty, r);      end
  def ep(*args); e_(l, :must_be,       r);      end

  def test_re_msg
    assert_re(:RE_MSG,
              "redundant message?",
              a(s(:lit, 42), s(:str, "message")),
              a(s(:lit, 42)))
  end

  def test_re_not
    assert_re(:RE_NOT,
              "refute not_cond",
              a(s(:call, s(:lit, 42), :!)),
              r(s(:lit, 42)))
  end

  def test_re_equal
    assert_re(:RE_EQUAL,
              "assert_equal exp, act",
              a(s(:call, :lhs, :==, :rhs)),
              ae(:lhs, :rhs))
  end

  def test_re_nequal
    assert_re(:RE_NEQUAL,
              "refute_equal exp, act",
              a(s(:call, :lhs, :!=, :rhs)),
              c(:refute_equal, :lhs, :rhs))
  end

  def test_re_incl
    assert_re(:RE_INCL,
              "assert_includes obj, val",
              a(s(:call, :lhs, :include?, :rhs)),
              ai(:lhs, :rhs))
  end

  def test_re_pred
    assert_re(:RE_PRED,
              "assert_predicate obj, msg",
              a(s(:call, :lhs, :pred?)),
              c(:assert_predicate, :lhs, s(:lit, :pred?)))
  end

  def test_re_oper
    assert_re(:RE_OPER,
              "assert_operator obj, msg, arg",
              a(s(:call, :lhs, :op, :rhs)),
              c(:assert_operator, :lhs, s(:lit, :op), :rhs))
  end

  def test_re_eq_msg
    assert_re(:RE_EQ_MSG,
              "redundant message?",
              ae(:lhs, :rhs, :msg),
              ae(:lhs, :rhs))
  end

  def test_re_eq_nil
    assert_re(:RE_EQ_NIL,
              "assert_nil obj",
              ae(s(:nil), :whatever),
              c(:assert_nil, :whatever))
  end

  def test_re_eq_pred
    assert_re(:RE_EQ_PRED,
              "assert_predicate obj, msg",
              ae(s(:true), s(:call, :obj, :msg)),
              c(:assert_predicate, :obj, s(:lit, :msg)))
  end

  def test_re_eq_oper
    assert_re(:RE_EQ_OPER,
              "assert_operator obj, msg, arg",
              ae(s(:true), s(:call, :obj, :msg, :rhs)),
              c(:assert_operator, :obj, s(:lit, :msg), :rhs))
  end

  def test_re_eq_lhs_str
    long = "string " * 100
    short = long[0, 20]

    assert_re(:RE_EQ_LHS_STR,
              "assert_includes actual, substr",
              ae(s(:str, long), :rhs),
              ai(:rhs, s(:str, short)))
  end

  def test_re_eq_rhs_lit
    assert_re(:RE_EQ_RHS_LIT,
              "assert_equal exp, act",
              ae(:lhs, s(:lit, :rhs)),
              ae(s(:lit, :rhs), :lhs))
  end

  def test_re_eq_rhs_str
    assert_re(:RE_EQ_RHS_STR,
              "assert_equal exp, act",
              ae(:lhs, s(:str, "str")),
              ae(s(:str, "str"), :lhs))
  end

  def test_re_eq_rhs_ntf__nil
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal exp, act",
              ae(:lhs, s(:nil)),
              ae(s(:nil), :lhs))
  end

  def test_re_eq_rhs_ntf__true
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal exp, act",
              ae(:lhs, s(:true)),
              ae(s(:true), :lhs))
  end

  def test_re_eq_rhs_ntf__false
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal exp, act",
              ae(:lhs, s(:false)),
              ae(s(:false), :lhs))
  end

  def test_re_eq_empty
    assert_re(:RE_EQ_EMPTY,
              "assert_empty",
              ae(s(:lit, 0), s(:call, :whatever, :length)),
              c(:assert_empty, :whatever))
  end

  def test_re_ref_msg
    assert_re(:RE_REF_MSG,
              "redundant message?",
              r(:test, s(:str, "msg")),
              r(:test))
  end

  def test_re_ref_not
    assert_re(:RE_REF_NOT,
              "assert cond",
              r(s(:call, s(:lit, 42), :!)),
              a(s(:lit, 42)))
  end

  def test_re_ref_incl
    assert_re(:RE_REF_INCL,
              "refute_includes obj, val",
              r(s(:call, :lhs, :include?, :rhs)),
              c(:refute_includes, :lhs, :rhs))
  end

  def test_re_ref_pred
    assert_re(:RE_REF_PRED,
              "refute_predicate obj, msg",
              r(s(:call, :lhs, :pred?)),
              c(:refute_predicate, :lhs, s(:lit, :pred?)))
  end

  def test_re_ref_oper
    assert_re(:RE_REF_OPER,
              "refute_operator obj, msg, arg",
              r(s(:call, :lhs, :op, :rhs)),
              c(:refute_operator, :lhs, s(:lit, :op), :rhs))
  end

  def test_re_op_incl
    assert_re(:RE_OP_INCL,
              "assert_includes enum, val",
              c(:assert_operator, :lhs, s(:lit, :include?), :rhs),
              ai(:lhs, :rhs))
  end

  def test_must_plain
    assert_re(:RE_MUST_PLAIN,
              "_(act).must_equal exp",
              s(:call,
                s(:call, s(:call, s(:call, nil, :a), :b), :c),
                :must_equal,
                s(:call, nil, :d)),
              # =>
              s(:call,
                s(:call, nil, :_,
                  s(:call, s(:call, s(:call, nil, :a), :b), :c)),
                :must_equal,
                s(:call, nil, :d)))
  end

  def test_must_plain_good
    assert_re_done(:RE_MUST_GOOD,
                   eq(s(:call, s(:call, s(:call, nil, :a), :b), :c),
                      s(:call, nil, :d)))
  end

  def test_must_plain_expect
    assert_re(:RE_MUST_OTHER,
              "_(act).must_equal exp",
              s(:call,
                s(:call, nil, :expect,
                  s(:call, s(:call, s(:call, nil, :a), :b), :c)),
                :must_equal,
                s(:call, nil, :d)),
              # =>
              eq(s(:call, s(:call, s(:call, nil, :a), :b), :c),
                 s(:call, nil, :d)))
  end

  def test_must_plain_value
    assert_re(:RE_MUST_OTHER,
              "_(act).must_equal exp",
              s(:call,
                s(:call, nil, :value,
                  s(:call, s(:call, s(:call, nil, :a), :b), :c)),
                :must_equal,
                s(:call, nil, :d)),
              # =>
              eq(s(:call, s(:call, s(:call, nil, :a), :b), :c),
                 s(:call, nil, :d)))
  end

  def test_must_equal_nil
    assert_re(:RE_MUST_EQ_NIL,
              "_(act).must_be_nil",
              eq(s(:call, s(:call, s(:call, nil, :a), :b), :c),
                 s(:nil)),
              # =>
              e_(s(:call, s(:call, s(:call, nil, :a), :b), :c),
                 :must_be_nil))
  end

  def test_re_plain
    assert_re(:RE_PLAIN,
              "Try to not use plain assert",
              a(:whatever),
              a(:whatever))
  end

  todo :assert
  todo :assert_empty
  # todo :assert_equal
  # todo :assert_equal_nil
  # todo :assert_equal_pred
  # todo :assert_equal_oper
  # todo :assert_equal_lhs_str
  # todo :assert_equal_rhs_lit
  # todo :assert_equal_rhs_str
  # todo :assert_equal_rhs_ntf__nil
  # todo :assert_equal_rhs_ntf__true
  # todo :assert_equal_rhs_ntf__false
  # todo :assert_equal_empty
  todo :assert_in_delta
  todo :assert_in_epsilon
  todo :assert_includes
  todo :assert_instance_of
  todo :assert_kind_of
  todo :assert_match
  todo :assert_nil
  todo :assert_operator
  todo :assert_output
  todo :assert_predicate
  todo :assert_raises
  todo :assert_respond_to
  todo :assert_same
  todo :assert_send
  todo :assert_silent
  todo :assert_throws
  todo :refute
  todo :refute_empty
  todo :refute_equal
  todo :refute_in_delta
  todo :refute_in_epsilon
  todo :refute_includes
  todo :refute_instance_of
  todo :refute_kind_of
  todo :refute_match
  todo :refute_nil
  todo :refute_operator
  todo :refute_predicate
  todo :refute_respond_to
  todo :refute_same

  todo :must_equal
  todo :must_equal_true
  todo :must_equal_false
  todo :must_equal_pred
  todo :must_equal_oper

  todo :must_equal_big_string
  todo :must_equal_assert_equal?
  todo :must_equal_lhs_str
  todo :must_equal_rhs_lit
  todo :must_equal_rhs_str
  todo :must_equal_rhs_ntf__nil
  todo :must_equal_rhs_ntf__true
  todo :must_equal_rhs_ntf__false
  todo :must_equal_empty

  todo :must_be_empty
  todo :must_be_close_to
  todo :must_be_within_epsilon
  todo :must_include
  todo :must_be_instance_of
  todo :must_be_kind_of
  todo :must_match
  todo :must_be
  todo :must_output
  todo :must_raise
  todo :must_respond_to
  todo :must_be_same_as
  todo :must_be_silent
  todo :must_throw

  todo :wont_be_empty
  todo :wont_equal
  todo :wont_be_close_to
  todo :wont_be_within_epsilon
  todo :wont_include
  todo :wont_be_instance_of
  todo :wont_be_kind_of
  todo :wont_match
  todo :wont_be_nil
  todo :wont_be
  todo :wont_respond_to
  todo :wont_be_same_as
end
