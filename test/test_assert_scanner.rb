#!/usr/bin/env ruby -Ilib -w

require "minitest/autorun"
require "minitest_lint/assert_scanner"

$v = true # enables "redundant message" phase

class TestAssertScanner < Minitest::Test
  AssertScanner = MinitestLint::AssertScanner

  make_my_diffs_pretty!

  def self.todo msg
    define_method "test_#{msg}" do
      skip "not yet"
    end
  end

  def self.todo! msg
    define_method "test_#{msg}" do
      puts
      puts <<~"EOM"
        def test_#{msg}
          assert_re(:RE_#{msg.to_s.upcase.delete_prefix("ASSERT_")},
                    "assert_xxx lhs, rhs",
                    a(c(:lhs, :xxx, :rhs)),
                    # =>
                    c(:assert_xxx, :lhs, :rhs))
        end
      EOM
      puts
      flunk "gonna do this next!"
    end
  end

  def a_lit a, l, m, *r; c(a, l, lit(m), *r); end

  def c(msg, *args); s(:call, nil, msg, *args);  end
  def a(*args);      c(:assert, *args);          end
  def r(*args);      c(:refute, *args);          end
  def e(l,m,*r);     s(:call, c(:_, l), m, *r);  end
  def aeq(*args);    c(:assert_equal, *args);    end
  def ain(*args);    c(:assert_includes, *args); end
  def aop(l, m, r);  a_lit(:assert_operator,  l, m, r); end
  def apr(l, m);     a_lit(:assert_predicate, l, m);    end
  def blk(*a);       s(:iter, c(:_), 0, *a);     end
  def bm(*a, m, r);  s(:call, blk(*a), m, r);    end
  def bmx(*a, m);    s(:call, blk(*a), m);    end
  def lit(x);        s(:lit, x);                 end
  def mbe(l, m, *r); e(l, :must_be, lit(m), *r); end
  def meq(l,r);      e(l, :must_equal,    r);    end
  def req(*args);    c(:refute_equal, *args);    end
  def rin(*args);    c(:refute_includes, *args); end
  def rop(l, m, r);  a_lit(:refute_operator,  l, m, r); end
  def rpr(l, m);     a_lit(:refute_predicate, l, m);    end
  def wbe(l, m, *r); e(l, :wont_be, lit(m), *r); end
  def weq(l,r);      e(l, :wont_equal,    r);    end

  def bad_blk blk_msg, lhs, msg, rhs
    blk = Symbol === blk_msg ? s(:call, nil, blk_msg) : blk_msg

    e(s(:iter, blk, 0, lhs), msg, rhs)
  end

  def bad_lam lhs, msg, *rhs
    e(s(:iter, s(:lambda), s(:args), lhs), msg, *rhs)
  end

  def assert_pattern scanner, from, msg = nil, to = nil
    pattern = AssertScanner.const_get scanner
    scan = AssertScanner.new
    proc = AssertScanner::SCANNERS[pattern]

    scan.instance_exec from, &proc

    assert_operator pattern, :===, from
    assert_match pattern, from

    if msg && to
      exp = {to => msg}

      assert_equal exp, scan.io
    else
      assert_empty scan.io
    end
  end

  def assert_re scanner, msg, from, to
    assert_pattern scanner, from, msg, to
  end

  def assert_re_done scanner, from
    assert_pattern scanner, from
  end

  def assert_nothing sexp
    scan = AssertScanner.new

    scan.analyze_assert sexp

    assert_empty scan.io
  end

  def refute_re scanner, from
    pattern = AssertScanner.const_get scanner

    refute_operator pattern, :===, from
    refute_match pattern, from
  end

  ######################################################################
  # Sanity Test:

  def test_000_sanity
    ruby = %(assert [1, 2, 3].include?(b) == true, "is b in 1..3?")
    sexp = RubyParser.new.process ruby
    scan = AssertScanner.new

    scan.analyze_assert sexp

    lhs = s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3))
    rhs = c(:b)
    inc = s(:call, lhs, :include?, rhs)

    exp = {
      c(:assert, s(:call, inc, :==, s(:true))) => "redundant message?",
      c(:assert_operator, inc, lit(:==), s(:true))  => "assert_operator obj, :msg, val",
      c(:assert_equal, inc, s(:true))          => "assert_equal exp, act",
      c(:assert_equal, s(:true), inc)          => "assert_equal lit, act",
      aop(lhs, :include?, rhs)                 => "assert_operator obj, :msg, val",
      c(:assert_includes, lhs, rhs)            => "assert_includes obj, val",
    }

    assert_equal exp, scan.io

    exp = [
      #  assert([1, 2, 3].include?(b) == true, "is b in 1..3?") # original
      "  assert(([1, 2, 3].include?(b) == true))           # redundant message?",
      "  assert_operator([1, 2, 3].include?(b), :==, true) # assert_operator obj, :msg, val",
      "  assert_equal([1, 2, 3].include?(b), true)         # assert_equal exp, act",
      "  assert_equal(true, [1, 2, 3].include?(b))         # assert_equal lit, act",
      "  assert_operator([1, 2, 3], :include?, b)          # assert_operator obj, :msg, val",
      "  assert_includes([1, 2, 3], b)                     # assert_includes obj, val",
    ]

    assert_equal exp, scan.out
  end

  def test_001_sanity
    ruby = %(expect([1, 2, 3].include?(b)).must_equal true, "is b in 1..3?") # TODO
    ruby = %(expect([1, 2, 3].include?(b)).must_equal true)

    sexp = RubyParser.new.process ruby
    scan = AssertScanner.new

    scan.analyze_assert sexp

    lhs = s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3))
    rhs = c(:b)
    inc = s(:call, lhs, :include?, rhs)

    exp = {
      e(inc, :must_equal, s(:true))             => "_(obj).must_<something> val",
      mbe(lhs, :include?, rhs)                  => "_(obj).must_be :msg, val",
      e(lhs, :must_include, rhs)                => "_(obj).must_include val"
    }

    assert_equal exp, scan.io

    exp = [
      #  expect([1, 2, 3].include?(b)).must_equal true # original
      "  _([1, 2, 3].include?(b)).must_equal(true) # _(obj).must_<something> val",
      "  _([1, 2, 3]).must_be(:include?, b)        # _(obj).must_be :msg, val",
      "  _([1, 2, 3]).must_include(b)              # _(obj).must_include val"
    ]

    assert_equal exp, scan.out
  end

  ######################################################################
  # Positive Assertions

  def test_assert
    assert_re(:RE_PLAIN,
              "Try to not use plain assert",
              a(:whatever),
              # =>
              a(:whatever))
  end

  def test_assert__msg
    assert_re(:RE_MSG,
              "redundant message?",
              a(:lhs, s(:str, "message")),
              # =>
              a(:lhs))
  end

  def test_assert__not
    assert_re(:RE_NOT,
              "refute obj",
              a(s(:call, :lhs, :!)),
              # =>
              r(:lhs))
  end

  def test_assert__operator
    assert_re(:RE_OPER,
              "assert_operator obj, :msg, val",
              a(s(:call, :lhs, :msg, :rhs)),
              # =>
              aop(:lhs, :msg, :rhs))
  end

  def test_assert__predicate
    assert_re(:RE_PRED,
              "assert_predicate obj, :pred?",
              a(s(:call, :lhs, :pred?)),
              # =>
              apr(:lhs, :pred?))
  end

  def test_assert_equal__array
    assert_re(:RE_EQ_EMPTY_LIT,
              "assert_empty obj",
              aeq(s(:array), :lhs),
              # =>
              c(:assert_empty, :lhs))
  end

  def test_assert_equal__class_name
    assert_re(:RE_EQ_CLASS_NAME,
              "assert_instance_of cls, obj",
              aeq(s(:str, "Woot"),
                  s(:call, s(:call, :rhs, :class), :name)),
              # =>
              c(:assert_instance_of, s(:const, :Woot), :rhs))
  end

  def test_assert_equal__class_name_namespaced
    assert_re(:RE_EQ_CLASS_NAME,
              "assert_instance_of cls, obj",
              aeq(s(:str, "X::Y::Z"),
                  s(:call, s(:call, :rhs, :class), :name)),
              # =>
              c(:assert_instance_of, s(:colon2, s(:colon2, s(:const, :X), :Y), :Z), :rhs))
  end

  def test_assert_equal__count_0
    assert_re(:RE_EQ_EMPTY,
              "assert_empty obj",
              aeq(lit(0), s(:call, :whatever, :count)),
              # =>
              c(:assert_empty, :whatever))
  end

  def test_assert_equal__float
    assert_re(:RE_EQ_FLOAT,
              "assert_in_epsilon float_lit, act",
              aeq(s(:lit, 6.28), :rhs),
              # =>
              c(:assert_in_epsilon, s(:lit, 6.28), :rhs))
  end

  def test_assert_equal__hash
    assert_re(:RE_EQ_EMPTY_LIT,
              "assert_empty obj",
              aeq(s(:hash), :lhs),
              # =>
              c(:assert_empty, :lhs))
  end

  def test_assert_equal__length_0
    assert_re(:RE_EQ_EMPTY,
              "assert_empty obj",
              aeq(lit(0), s(:call, :whatever, :length)),
              # =>
              c(:assert_empty, :whatever))
  end

  def test_assert_equal__lhs_str
    long = "string " * 100
    short = long[0, 20]

    assert_re(:RE_EQ_LHS_STR,
              "assert_includes str, 'substr'",
              aeq(s(:str, long), :rhs),
              # =>
              ain(:rhs, s(:str, short)))
  end

  def test_assert_equal__msg
    assert_re(:RE_EQ_MSG,
              "redundant message?",
              aeq(:lhs, :rhs, :msg),
              # =>
              aeq(:lhs, :rhs))
  end

  def test_assert_equal__nil
    assert_re(:RE_EQ_NIL,
              "assert_nil obj",
              aeq(s(:nil), :whatever),
              # =>
              c(:assert_nil, :whatever))
  end

  def test_assert_equal__oper_false
    assert_re(:RE_NEQ_OPER,
              "refute_operator obj, :msg, val",
              aeq(s(:false), s(:call, :obj, :msg, :rhs)),
              # =>
              rop(:obj, :msg, :rhs))
  end

  def test_assert_equal__oper_true
    assert_re(:RE_EQ_OPER,
              "assert_operator obj, :msg, val",
              aeq(s(:true), s(:call, :obj, :msg, :rhs)),
              # =>
              aop(:obj, :msg, :rhs))
  end

  def test_assert_equal__pred_false
    assert_re(:RE_NEQ_PRED,
              "refute_predicate obj, :pred?",
              aeq(s(:false), s(:call, :obj, :msg)),
              # =>
              rpr(:obj, :msg))
  end

  def test_assert_equal__pred_true
    assert_re(:RE_EQ_PRED,
              "assert_predicate obj, :pred?",
              aeq(s(:true), s(:call, :obj, :msg)),
              # =>
              apr(:obj, :msg))
  end

  def test_assert_equal__rhs_lit
    assert_re(:RE_EQ_RHS_LIT,
              "assert_equal lit, act",
              aeq(:act, lit(:val)),
              # =>
              aeq(lit(:val), :act))
  end

  def test_assert_equal__rhs_ntf__false
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal lit, act",
              aeq(:act, s(:false)),
              # =>
              aeq(s(:false), :act))
  end

  def test_assert_equal__rhs_ntf__lit_true
    assert_nothing aeq(s(:lit, 42), s(:true))
  end

  def test_assert_equal__rhs_ntf__nil
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal lit, act",
              aeq(:act, s(:nil)),
              # =>
              aeq(s(:nil), :act))
  end

  def test_assert_equal__rhs_ntf__true
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal lit, act",
              aeq(:act, s(:true)),
              # =>
              aeq(s(:true), :act))
  end

  def test_assert_equal__rhs_ntf__true_true
    assert_nothing aeq(s(:true), s(:true))
  end

  def test_assert_equal__rhs_str
    assert_re(:RE_EQ_RHS_STR,
              "assert_equal lit, act",
              aeq(:act, s(:str, "str")),
              # =>
              aeq(s(:str, "str"), :act))
  end

  def test_assert_equal__size_0
    assert_re(:RE_EQ_EMPTY,
              "assert_empty obj",
              aeq(lit(0), s(:call, :whatever, :size)),
              # =>
              c(:assert_empty, :whatever))
  end

  def test_assert_in_delta
    assert_re(:RE_IN_DELTA,
              "assert_in_epsilon float_lit, act",
              c(:assert_in_delta, :lhs, :rhs),
              # =>
              c(:assert_in_epsilon, :lhs, :rhs))
  end

  def test_assert_operator__eq
    assert_re(:RE_OPER_MATCH_EQ,
              "assert_equal exp, act",
              aop(:lhs, :==, :rhs),
              # =>
              c(:assert_equal, :lhs, :rhs))
  end

  def test_assert_operator__file_exist
    assert_re(:RE_OPER_FILE_EXIST,
              "assert_path_exists val",
              aop(s(:const, :File), :exist?, :rhs),
              # =>
              c(:assert_path_exists, :rhs))
  end

  def test_assert_operator__include
    assert_re(:RE_OPER_INCLUDE,
              "assert_includes obj, val",
              aop(:lhs, :include?, :rhs),
              # =>
              ain(:lhs, :rhs))
  end

  def test_assert_operator__instance_of
    assert_re(:RE_OPER_INSTANCE_OF,
              "assert_instance_of cls, obj",
              aop(:obj, :instance_of?, :cls),
              # =>
              c(:assert_instance_of, :cls, :obj))
  end

  def test_assert_operator__is_a
    assert_re(:RE_OPER_IS_A,
              "assert_kind_of mod, obj",
              aop(:obj, :is_a?, :mod),
              # =>
              c(:assert_kind_of, :mod, :obj))
  end

  def test_assert_operator__key
    assert_re(:RE_OPER_KEY,
              "assert_includes obj, val",
              aop(:lhs, :key?, :rhs),
              # =>
              ain(:lhs, :rhs))
  end

  def test_assert_operator__kind_of
    assert_re(:RE_OPER_KIND_OF,
              "assert_kind_of mod, obj",
              aop(:obj, :kind_of?, :mod),
              # =>
              c(:assert_kind_of, :mod, :obj))
  end

  def test_assert_operator__match_eq3
    assert_re(:RE_OPER_MATCH_EQ3,
              "assert_match obj, val",
              aop(:lhs, :===, :rhs),
              # =>
              c(:assert_match, :lhs, :rhs))
  end

  def test_assert_operator__match_equalstilde
    assert_re(:RE_OPER_MATCH_EQTILDE,
              "assert_match obj, val",
              aop(:lhs, :=~, :rhs),
              # =>
              c(:assert_match, :lhs, :rhs))
  end

  def test_assert_operator__match_match
    assert_re(:RE_OPER_MATCH_MATCH,
              "assert_match obj, val",
              aop(:lhs, :match, :rhs),
              # =>
              c(:assert_match, :lhs, :rhs))
  end

  def test_assert_operator__match_match_eh
    assert_re(:RE_OPER_MATCH_MATCH_EH,
              "assert_match obj, val",
              aop(:lhs, :match?, :rhs),
              # =>
              c(:assert_match, :lhs, :rhs))
  end

  def test_assert_operator__match_not_tilde
    assert_re(:RE_OPER_MATCH_NOT_TILDE,
              "refute_match obj, val",
              aop(:lhs, :!~, :rhs),
              # =>
              c(:refute_match, :lhs, :rhs))
  end

  def test_assert_operator__neq
    assert_re(:RE_OPER_MATCH_NEQ,
              "refute_equal exp, act",
              aop(:lhs, :!=, :rhs),
              # =>
              c(:refute_equal, :lhs, :rhs))
  end

  def test_assert_operator__respond_to
    assert_re(:RE_OPER_RESPOND_TO,
              "assert_respond_to obj, val",
              aop(:obj, :respond_to?, :msg),
              # =>
              c(:assert_respond_to, :obj, :msg))
  end

  def test_assert_operator__same
    assert_re(:RE_OPER_SAME,
              "assert_same obj, val",
              aop(:obj, :equal?, :val),
              # =>
              c(:assert_same, :obj, :val))
  end

  def test_assert_predicate__empty
    assert_re(:RE_PRED_EMPTY,
              "assert_empty obj",
              apr(:lhs, :empty?),
              # =>
              c(:assert_empty, :lhs))
  end

  def test_assert_predicate__nil
    assert_re(:RE_PRED_NIL,
              "assert_nil obj",
              apr(:lhs, :nil?),
              # =>
              c(:assert_nil, :lhs))
  end

  ######################################################################
  # Positive Expectations

  todo :must_equal
  todo :must_equal__big_string
  todo :must_equal__false
  todo :must_equal__lhs_str
  todo :must_equal__rhs_lit
  todo :must_equal__rhs_str
  todo :must_equal__true
  todo :must_equal__class_name

  def test_must__plain
    assert_re(:RE_MUST_PLAIN,
              "_(obj).must_<something>",
              s(:call, :lhs, :must_whatevs),
              # =>
              e(:lhs, :must_whatevs))
  end

  def test_must__plain_rhs
    assert_re(:RE_MUST_PLAIN_RHS,
              "_(obj).must_<something> val",
              s(:call, :lhs, :must_equal, :rhs),
              # =>
              meq(:lhs, :rhs))
  end

  def test_must__plain_bad
    refute_re(:RE_MUST_PLAIN,
              e(:lhs, :must_equal, lit(42)))
  end

  def test_must__plain_block
    # _ { lhs }.must_xxx rhs
    refute_re(:RE_MUST_PLAIN,
              s(:call, blk(c(:lhs)), :must_xxx, :rhs))
  end

  def test_must__plain_expect
    assert_re(:RE_MUST_OTHER,
              "_(obj).must_<something> val",
              s(:call, c(:expect, :act), :must_be, lit(:<), :arg),
              # =>
              mbe(:act, :<, :arg))
  end

  def test_must__plain_value
    assert_re(:RE_MUST_OTHER,
              "_(obj).must_<something> val",
              s(:call, c(:value, :act), :must_equal, :exp),
              # =>
              meq(:act, :exp))
  end

  def test_must_be__empty
    assert_re(:RE_MUST_BE__EMPTY,
              "_(obj).must_be_empty",
              mbe(:lhs, :empty?),
              # =>
              e(:lhs, :must_be_empty))
  end

  def test_must_be__eq
    assert_re(:RE_MUST_BE__EQ,
              "_(obj).must_equal val",
              mbe(:lhs, :==, :rhs),
              # =>
              e(:lhs, :must_equal, :rhs))
  end

  def test_must_be__eq__float
    assert_re(:RE_MUST_BE__EQ__FLOAT,
              "_(obj).must_be_within_epsilon float_lit",
              mbe(:lhs, :==, s(:lit, 6.28)),
              # =>
              e(:lhs, :must_be_within_epsilon, s(:lit, 6.28)))
  end

  def test_must_be__eq_not
    assert_re(:RE_MUST_BE__NEQ,
              "_(obj).wont_equal val",
              mbe(:lhs, :!=, :rhs),
              # =>
              e(:lhs, :wont_equal, :rhs))
  end

  def test_must_be__file_exist
    assert_re(:RE_MUST_BE_FILE_EXIST,
              "_(val).path_must_exist",
              mbe(s(:const, :File), :exist?, :rhs),
              # =>
              e(:rhs, :path_must_exist))
  end

  def test_must_be__include
    assert_re(:RE_MUST_BE__INCLUDE,
              "_(obj).must_include val",
              mbe(:lhs, :include?, :rhs),
              # =>
              e(:lhs, :must_include, :rhs))
  end

  def test_must_be__instance_of
    assert_re(:RE_MUST_BE__INSTANCE_OF,
              "_(obj).must_be_instance_of val",
              mbe(:lhs, :instance_of?, :rhs),
              # =>
              e(:lhs, :must_be_instance_of, :rhs))
  end

  def test_must_be__is_a
    assert_re(:RE_MUST_BE__IS_A,
              "_(obj).must_be_kind_of val",
              mbe(:lhs, :is_a?, :rhs),
              # =>
              e(:lhs, :must_be_kind_of, :rhs))
  end

  def test_must_be__key
    assert_re(:RE_MUST_BE__KEY,
              "_(obj).must_include val",
              mbe(:lhs, :key?, :rhs),
              # =>
              e(:lhs, :must_include, :rhs))
  end

  def test_must_be__kind_of
    assert_re(:RE_MUST_BE__KIND_OF,
              "_(obj).must_be_kind_of val",
              mbe(:lhs, :kind_of?, :rhs),
              # =>
              e(:lhs, :must_be_kind_of, :rhs))
  end

  def test_must_be__match_eq3
    assert_re(:RE_MUST_MATCH_EQ3,
              "_(obj).must_match val",
              mbe(:lhs, :===, :rhs),
              # =>
              e(:lhs, :must_match, :rhs))
  end

  def test_must_be__match_equalstilde
    assert_re(:RE_MUST_MATCH_EQTILDE,
              "_(obj).must_match val",
              mbe(:lhs, :=~, :rhs),
              # =>
              e(:lhs, :must_match, :rhs))
  end

  def test_must_be__match_match
    assert_re(:RE_MUST_MATCH_MATCH,
              "_(obj).must_match val",
              mbe(:lhs, :match, :rhs),
              # =>
              e(:lhs, :must_match, :rhs))
  end

  def test_must_be__match_match_eh
    assert_re(:RE_MUST_MATCH_MATCH_EH,
              "_(obj).must_match val",
              mbe(:lhs, :match?, :rhs),
              # =>
              e(:lhs, :must_match, :rhs))
  end

  def test_must_be__match_not_tilde
    assert_re(:RE_MUST_MATCH_NOT_TILDE,
              "_(obj).wont_match val",
              mbe(:lhs, :!~, :rhs),
              # =>
              e(:lhs, :wont_match, :rhs))
  end

  def test_must_be__nil
    assert_re(:RE_MUST_BE__NIL,
              "_(obj).must_be_nil",
              mbe(:lhs, :nil?),
              # =>
              e(:lhs, :must_be_nil))
  end

  def test_must_be__respond_to
    assert_re(:RE_MUST_BE__RESPOND_TO,
              "_(obj).must_respond_to val",
              mbe(:lhs, :respond_to?, :rhs),
              # =>
              e(:lhs, :must_respond_to, :rhs))
  end

  def test_must_be__same
    assert_re(:RE_MUST_BE__EQUAL,
              "_(obj).must_be_same_as val",
              mbe(:obj, :equal?, :val),
              # =>
              e(:obj, :must_be_same_as, :val))
  end

  def test_must_be_close_to
    assert_re(:RE_MUST_BE_CLOSE_TO,
              "_(obj).must_be_within_epsilon float_lit",
              e(:lhs, :must_be_close_to, :rhs),
              # =>
              e(:lhs, :must_be_within_epsilon, :rhs))
  end

  def test_must_be_silent__lambda_stabby
    # _(->() { 42 }).must_be_silent
    assert_re(:RE_MUST_LAMBDA,
              "_{ ... }.must_<something>",
              bad_lam(:lhs, :must_be_silent),
              # =>
              bmx(:lhs, :must_be_silent))
  end

  def test_must_equal__array
    assert_re(:RE_MUST_BE_EMPTY_LIT,
              "_(obj).must_be_empty",
              meq(:lhs, s(:array)),
              # =>
              e(:lhs, :must_be_empty))
  end

  def test_must_equal__count_0
    assert_re(:RE_MUST_SIZE_ZERO,
              "_(obj).must_be_empty",
              meq(s(:call, :lhs, :count), lit(0)),
              # =>
              e(:lhs, :must_be_empty))
  end

  def test_must_equal__float
    assert_re(:RE_MUST_EQ_FLOAT,
              "_(obj).must_be_close_to float_lit",
              meq(:lhs, s(:lit, 6.28)),
              # =>
              e(:lhs, :must_be_close_to, s(:lit, 6.28)))
  end

  def test_must_equal__hash
    assert_re(:RE_MUST_BE_EMPTY_LIT,
              "_(obj).must_be_empty",
              meq(:lhs, s(:hash)),
              # =>
              e(:lhs, :must_be_empty))
  end

  def test_must_equal__length_0
    assert_re(:RE_MUST_SIZE_ZERO,
              "_(obj).must_be_empty",
              meq(s(:call, :lhs, :length), lit(0)),
              # =>
              e(:lhs, :must_be_empty))
  end

  def test_must_equal__nil
    assert_re(:RE_MUST_EQ_NIL,
              "_(obj).must_be_nil",
              meq(:lhs, s(:nil)),
              # =>
              e(:lhs, :must_be_nil))
  end

  def test_must_equal__oper
    assert_re(:RE_MUST_BE_OPER,
              "_(obj).must_be :msg, val",
              meq(s(:call, :lhs, :msg, :rhs), s(:true)),
              # =>
              mbe(:lhs, :msg, :rhs))
  end

  def test_must_equal__oper_f
    assert_re(:RE_MUST_BE_OPER_F,
              "_(obj).wont_be :msg, val",
              meq(s(:call, :lhs, :msg, :rhs), s(:false)),
              # =>
              wbe(:lhs, :msg, :rhs))
  end

  def test_must_equal__pred
    assert_re(:RE_MUST_BE_PRED,
              "_(obj).must_be :pred?",
              meq(s(:call, :lhs, :pred?), s(:true)),
              # =>
              mbe(:lhs, :pred?))
  end

  def test_must_equal__pred_f
    assert_re(:RE_MUST_BE_PRED_F,
              "_(obj).wont_be :pred?",
              meq(s(:call, :lhs, :pred?), s(:false)),
              # =>
              wbe(:lhs, :pred?))
  end

  def test_must_equal__size_0
    assert_re(:RE_MUST_SIZE_ZERO,
              "_(obj).must_be_empty",
              meq(s(:call, :lhs, :size), lit(0)),
              # =>
              e(:lhs, :must_be_empty))
  end

  def test_must_raise__lambda_lambda
    # _(proc { 42 }).must_raise Blah
    assert_re(:RE_MUST_LAMBDA_RHS,
              "_{ ... }.must_<something> val",
              bad_blk(:lambda, :lhs, :must_raise, :rhs),
              # =>
              bm(:lhs, :must_raise, :rhs))
  end

  def test_must_raise__lambda_proc
    # _(lambda { 42 }).must_raise Blah
    assert_re(:RE_MUST_LAMBDA_RHS,
              "_{ ... }.must_<something> val",
              bad_blk(:proc, :lhs, :must_raise, :rhs),
              # =>
              bm(:lhs, :must_raise, :rhs))
  end

  def test_must_raise__lambda_proc_new
    # _(Proc.new { 42 }).must_raise Blah
    assert_re(:RE_MUST_LAMBDA_RHS,
              "_{ ... }.must_<something> val",
              bad_blk(s(:call, s(:const, :Proc), :new), :lhs, :must_raise, :rhs),
              # =>
              bm(:lhs, :must_raise, :rhs))
  end

  def test_must_raise__lambda_stabby
    # _(->() { 42 }).must_raise Blah
    assert_re(:RE_MUST_LAMBDA_RHS,
              "_{ ... }.must_<something> val",
              bad_lam(:lhs, :must_raise, :rhs),
              # =>
              bm(:lhs, :must_raise, :rhs))
  end

  ######################################################################
  # Negative Assertions

  todo :refute_empty__obj_size_gt_zero__refute_empty
  todo :refute_empty__refute_equal_obj_size_ne_zero
  todo :refute_equal__class_name
  todo :refute_equal__class_name_namespaced
  todo :refute_nil
  todo :refute_operator__a_msg_b_eq_false

  def test_refute
    assert_re(:RE_REF_PLAIN,
              "Try to not use plain refute",
              r(:whatever),
              # =>
              r(:whatever))
  end

  def test_refute__msg
    assert_re(:RE_REF_MSG,
              "redundant message?",
              r(:test, s(:str, "msg")),
              # =>
              r(:test))
  end

  def test_refute__not
    assert_re(:RE_REF_NOT,
              "assert obj",
              r(s(:call, :lhs, :!)),
              # =>
              a(:lhs))
  end

  def test_refute__operator
    assert_re(:RE_REF_OPER,
              "refute_operator obj, :msg, val",
              r(s(:call, :lhs, :msg, :rhs)),
              # =>
              rop(:lhs, :msg, :rhs))
  end

  def test_refute__predicate
    assert_re(:RE_REF_PRED,
              "refute_predicate obj, :pred?",
              r(s(:call, :lhs, :msg?)),
              # =>
              rpr(:lhs, :msg?))
  end

  def test_refute_equal__array
    assert_re(:RE_REF_EQ_EMPTY_LIT,
              "refute_empty obj",
              req(s(:array), :lhs),
              # =>
              c(:refute_empty, :lhs))
  end

  def test_refute_equal__count_0
    assert_re(:RE_REF_EQ_EMPTY,
              "refute_empty obj",
              req(lit(0), s(:call, :whatever, :count)),
              # =>
              c(:refute_empty, :whatever))
  end

  def test_refute_equal__float
    assert_re(:RE_REF_EQ_FLOAT,
              "refute_in_epsilon float_lit, act",
              req(s(:lit, 6.28), :rhs),
              # =>
              c(:refute_in_epsilon, s(:lit, 6.28), :rhs))
  end

  def test_refute_equal__hash
    assert_re(:RE_REF_EQ_EMPTY_LIT,
              "refute_empty obj",
              req(s(:hash), :lhs),
              # =>
              c(:refute_empty, :lhs))
  end

  def test_refute_equal__length_0
    assert_re(:RE_REF_EQ_EMPTY,
              "refute_empty obj",
              req(lit(0), s(:call, :whatever, :length)),
              # =>
              c(:refute_empty, :whatever))
  end

  def test_refute_equal__lhs_str
    long = "string " * 100
    short = long[0, 20]

    assert_re(:RE_REF_EQ_LHS_STR,
              "refute_includes str, 'substr'",
              req(s(:str, long), :rhs),
              # =>
              rin(:rhs, s(:str, short)))
  end

  def test_refute_equal__msg
    assert_re(:RE_REF_EQ_MSG,
              "redundant message?",
              req(:lhs, :rhs, :msg),
              # =>
              req(:lhs, :rhs))
  end

  def test_refute_equal__nil
    assert_re(:RE_REF_EQ_NIL,
              "refute_nil obj",
              req(s(:nil), :whatever),
              # =>
              c(:refute_nil, :whatever))
  end

  def test_refute_equal__oper_false
    assert_re(:RE_REF_NEQ_OPER,
              "assert_operator obj, :msg, val",
              req(s(:false), s(:call, :obj, :msg, :rhs)),
              # =>
              aop(:obj, :msg, :rhs))
  end

  def test_refute_equal__oper_true
    assert_re(:RE_REF_EQ_OPER,
              "refute_operator obj, :msg, val",
              req(s(:true), s(:call, :obj, :msg, :rhs)),
              # =>
              rop(:obj, :msg, :rhs))
  end

  def test_refute_equal__pred_false
    assert_re(:RE_REF_NEQ_PRED,
              "assert_predicate obj, :pred?",
              req(s(:false), s(:call, :obj, :msg)),
              # =>
              apr(:obj, :msg))
  end

  def test_refute_equal__pred_true
    assert_re(:RE_REF_EQ_PRED,
              "refute_predicate obj, :pred?",
              req(s(:true), s(:call, :obj, :msg)),
              # =>
              rpr(:obj, :msg))
  end

  def test_refute_equal__rhs_lit
    assert_re(:RE_REF_EQ_RHS_LIT,
              "refute_equal lit, act",
              req(:act, lit(:val)),
              # =>
              req(lit(:val), :act))
  end

  def test_refute_equal__rhs_ntf__false
    assert_re(:RE_REF_EQ_RHS_NTF,
              "refute_equal lit, act",
              req(:act, s(:false)),
              # =>
              req(s(:false), :act))
  end

  def test_refute_equal__rhs_ntf__lit_true
    assert_nothing req(s(:lit, 42), s(:true))
  end

  def test_refute_equal__rhs_ntf__nil
    assert_re(:RE_REF_EQ_RHS_NTF,
              "refute_equal lit, act",
              req(:act, s(:nil)),
              # =>
              req(s(:nil), :act))
  end

  def test_refute_equal__rhs_ntf__true
    assert_re(:RE_REF_EQ_RHS_NTF,
              "refute_equal lit, act",
              req(:act, s(:true)),
              # =>
              req(s(:true), :act))
  end

  def test_refute_equal__rhs_ntf__true_true
    assert_nothing req(s(:true), s(:true))
  end

  def test_refute_equal__rhs_str
    assert_re(:RE_REF_EQ_RHS_STR,
              "refute_equal lit, act",
              req(:act, s(:str, "str")),
              # =>
              req(s(:str, "str"), :act))
  end

  def test_refute_equal__size_0
    assert_re(:RE_REF_EQ_EMPTY,
              "refute_empty obj",
              req(lit(0), s(:call, :whatever, :size)),
              # =>
              c(:refute_empty, :whatever))
  end

  def test_refute_in_delta
    assert_re(:RE_REF_IN_DELTA,
              "refute_in_epsilon float_lit, act",
              c(:refute_in_delta, :lhs, :rhs),
              # =>
              c(:refute_in_epsilon, :lhs, :rhs))
  end

  def test_refute_operator__eq
    assert_re(:RE_REF_OPER_MATCH_EQ,
              "refute_equal exp, act",
              rop(:lhs, :==, :rhs),
              # =>
              c(:refute_equal, :lhs, :rhs))
  end

  def test_refute_operator__file_exist
    assert_re(:RE_REF_OPER_FILE_EXIST,
              "refute_path_exists val",
              rop(s(:const, :File), :exist?, :rhs),
              # =>
              c(:refute_path_exists, :rhs))
  end

  def test_refute_operator__include
    assert_re(:RE_REF_OPER_INCLUDE,
              "refute_includes obj, val",
              rop(:lhs, :include?, :rhs),
              # =>
              c(:refute_includes, :lhs, :rhs))
  end

  def test_refute_operator__instance_of
    assert_re(:RE_REF_OPER_INSTANCE_OF,
              "refute_instance_of cls, obj",
              rop(:obj, :instance_of?, :cls),
              # =>
              c(:refute_instance_of, :cls, :obj))
  end

  def test_refute_operator__is_a
    assert_re(:RE_REF_OPER_IS_A,
              "refute_kind_of mod, obj",
              rop(:obj, :is_a?, :mod),
              # =>
              c(:refute_kind_of, :mod, :obj))
  end

  def test_refute_operator__key
    assert_re(:RE_REF_OPER_KEY,
              "refute_includes obj, val",
              rop(:lhs, :key?, :rhs),
              # =>
              c(:refute_includes, :lhs, :rhs))
  end

  def test_refute_operator__kind_of
    assert_re(:RE_REF_OPER_KIND_OF,
              "refute_kind_of mod, obj",
              rop(:obj, :kind_of?, :mod),
              # =>
              c(:refute_kind_of, :mod, :obj))
  end

  def test_refute_operator__match_eq3
    assert_re(:RE_REF_OPER_MATCH_EQ3,
              "refute_match obj, val",
              rop(:lhs, :===, :rhs),
              # =>
              c(:refute_match, :lhs, :rhs))
  end

  def test_refute_operator__match_equalstilde
    assert_re(:RE_REF_OPER_MATCH_EQTILDE,
              "refute_match obj, val",
              rop(:lhs, :=~, :rhs),
              # =>
              c(:refute_match, :lhs, :rhs))
  end

  def test_refute_operator__match_match
    assert_re(:RE_REF_OPER_MATCH_MATCH,
              "refute_match obj, val",
              rop(:lhs, :match, :rhs),
              # =>
              c(:refute_match, :lhs, :rhs))
  end

  def test_refute_operator__match_match_eh
    assert_re(:RE_REF_OPER_MATCH_MATCH_EH,
              "refute_match obj, val",
              rop(:lhs, :match?, :rhs),
              # =>
              c(:refute_match, :lhs, :rhs))
  end

  def test_refute_operator__match_not_tilde
    assert_re(:RE_REF_OPER_MATCH_NOT_TILDE,
              "assert_match obj, val",
              rop(:lhs, :!~, :rhs),
              # =>
              c(:assert_match, :lhs, :rhs))
  end

  def test_refute_operator__neq
    assert_re(:RE_REF_OPER_MATCH_NEQ,
              "assert_equal exp, act",
              rop(:lhs, :!=, :rhs),
              # =>
              c(:assert_equal, :lhs, :rhs))
  end

  def test_refute_operator__respond_to
    assert_re(:RE_REF_OPER_RESPOND_TO,
              "refute_respond_to obj, val",
              rop(:obj, :respond_to?, :msg),
              # =>
              c(:refute_respond_to, :obj, :msg))
  end

  def test_refute_operator__same
    assert_re(:RE_REF_OPER_SAME,
              "refute_same obj, val",
              rop(:obj, :equal?, :val),
              # =>
              c(:refute_same, :obj, :val))
  end

  def test_refute_predicate__empty
    assert_re(:RE_REF_PRED_EMPTY,
              "refute_empty val",
              rpr(:lhs, :empty?),
              # =>
              c(:refute_empty, :lhs))
  end

  def test_refute_predicate__nil
    assert_re(:RE_REF_PRED_NIL,
              "refute_nil val",
              rpr(:lhs, :nil?),
              # =>
              c(:refute_nil, :lhs))
  end

  ######################################################################
  # Negative Expectations

  todo :wont_be_silent__lambda_stabby
  todo :wont_equal
  todo :wont_equal__big_string
  todo :wont_equal__false
  todo :wont_equal__lhs_str
  todo :wont_equal__rhs_lit
  todo :wont_equal__rhs_str
  todo :wont_equal__true
  todo :wont_raise__lambda_lambda
  todo :wont_raise__lambda_proc
  todo :wont_raise__lambda_proc_new
  todo :wont_raise__lambda_stabby

  def test_wont__plain
    assert_re(:RE_WONT_PLAIN,
              "_(obj).wont_<something> val",
              s(:call, :lhs, :wont_equal, :rhs),
              # =>
              weq(:lhs, :rhs))
  end

  def test_wont__plain_bad
    refute_re(:RE_WONT_PLAIN,
              e(:lhs, :wont_equal, lit(42)))
  end

  def test_wont__plain_block
    # _ { lhs }.wont_xxx rhs
    refute_re(:RE_WONT_PLAIN,
              s(:call, blk(c(:lhs)), :wont_xxx, :rhs))
  end

  def test_wont__plain_expect
    assert_re(:RE_WONT_OTHER,
              "_(obj).wont_<something> val",
              s(:call, c(:expect, :act), :wont_be, lit(:<), :arg),
              # =>
              wbe(:act, :<, :arg))
  end

  def test_wont__plain_value
    assert_re(:RE_WONT_OTHER,
              "_(obj).wont_<something> val",
              s(:call, c(:value, :act), :wont_equal, :exp),
              # =>
              weq(:act, :exp))
  end

  def test_wont_be__empty
    assert_re(:RE_WONT_BE__EMPTY,
              "_(obj).wont_be_empty",
              wbe(:lhs, :empty?),
              # =>
              e(:lhs, :wont_be_empty))
  end

  def test_wont_be__eq
    assert_re(:RE_WONT_BE__EQ,
              "_(obj).wont_equal val",
              wbe(:lhs, :==, :rhs),
              # =>
              e(:lhs, :wont_equal, :rhs))
  end

  def test_wont_be__eq__float
    assert_re(:RE_WONT_BE__EQ__FLOAT,
              "_(obj).wont_be_within_epsilon float_lit",
              wbe(:lhs, :==, s(:lit, 6.28)),
              # =>
              e(:lhs, :wont_be_within_epsilon, s(:lit, 6.28)))
  end

  def test_wont_be__eq_not
    assert_re(:RE_WONT_BE__NEQ,
              "_(obj).must_equal val",
              wbe(:lhs, :!=, :rhs),
              # =>
              e(:lhs, :must_equal, :rhs))
  end

  def test_wont_be__file_exist
    assert_re(:RE_WONT_BE_FILE_EXIST,
              "_(val).path_wont_exist",
              wbe(s(:const, :File), :exist?, :rhs),
              # =>
              e(:rhs, :path_wont_exist))
  end

  def test_wont_be__include
    assert_re(:RE_WONT_BE__INCLUDE,
              "_(obj).wont_include val",
              wbe(:lhs, :include?, :rhs),
              # =>
              e(:lhs, :wont_include, :rhs))
  end

  def test_wont_be__instance_of
    assert_re(:RE_WONT_BE__INSTANCE_OF,
              "_(obj).wont_be_instance_of val",
              wbe(:lhs, :instance_of?, :rhs),
              # =>
              e(:lhs, :wont_be_instance_of, :rhs))
  end

  def test_wont_be__is_a
    assert_re(:RE_WONT_BE__IS_A,
              "_(obj).wont_be_kind_of val",
              wbe(:lhs, :is_a?, :rhs),
              # =>
              e(:lhs, :wont_be_kind_of, :rhs))
  end

  def test_wont_be__key
    assert_re(:RE_WONT_BE__KEY,
              "_(obj).wont_include val",
              wbe(:lhs, :key?, :rhs),
              # =>
              e(:lhs, :wont_include, :rhs))
  end

  def test_wont_be__kind_of
    assert_re(:RE_WONT_BE__KIND_OF,
              "_(obj).wont_be_kind_of val",
              wbe(:lhs, :kind_of?, :rhs),
              # =>
              e(:lhs, :wont_be_kind_of, :rhs))
  end

  def test_wont_be__match_eq3
    assert_re(:RE_WONT_BE__EQ3,
              "_(obj).wont_match val",
              wbe(:lhs, :===, :rhs),
              # =>
              e(:lhs, :wont_match, :rhs))
  end

  def test_wont_be__match_equalstilde
    assert_re(:RE_WONT_BE__EQTILDE,
              "_(obj).wont_match val",
              wbe(:lhs, :=~, :rhs),
              # =>
              e(:lhs, :wont_match, :rhs))
  end

  def test_wont_be__match_match
    assert_re(:RE_WONT_BE__MATCH,
              "_(obj).wont_match val",
              wbe(:lhs, :match, :rhs),
              # =>
              e(:lhs, :wont_match, :rhs))
  end

  def test_wont_be__match_match_eh
    assert_re(:RE_WONT_BE__MATCH_EH,
              "_(obj).wont_match val",
              wbe(:lhs, :match?, :rhs),
              # =>
              e(:lhs, :wont_match, :rhs))
  end

  def test_wont_be__match_not_tilde
    assert_re(:RE_WONT_MATCH_NOT_TILDE,
              "_(obj).must_match val",
              wbe(:lhs, :!~, :rhs),
              # =>
              e(:lhs, :must_match, :rhs))
  end

  def test_wont_be__nil
    assert_re(:RE_WONT_BE__NIL,
              "_(obj).wont_be_nil",
              wbe(:lhs, :nil?),
              # =>
              e(:lhs, :wont_be_nil))
  end

  def test_wont_be__respond_to
    assert_re(:RE_WONT_BE__RESPOND_TO,
              "_(obj).wont_respond_to val",
              wbe(:lhs, :respond_to?, :rhs),
              # =>
              e(:lhs, :wont_respond_to, :rhs))
  end

  def test_wont_be__same
    assert_re(:RE_WONT_BE__EQUAL,
              "_(obj).wont_be_same_as val",
              wbe(:obj, :equal?, :val),
              # =>
              e(:obj, :wont_be_same_as, :val))
  end

  def test_wont_be_close_to
    assert_re(:RE_WONT_BE_CLOSE_TO,
              "_(obj).wont_be_within_epsilon float_lit",
              e(:lhs, :wont_be_close_to, :rhs),
              # =>
              e(:lhs, :wont_be_within_epsilon, :rhs))
  end

  def test_wont_equal__array
    assert_re(:RE_WONT_BE_EMPTY_LIT,
              "_(obj).wont_be_empty",
              weq(:lhs, s(:array)),
              # =>
              e(:lhs, :wont_be_empty))
  end

  def test_wont_equal__count_0
    assert_re(:RE_WONT_SIZE_ZERO,
              "_(obj).wont_be_empty",
              weq(s(:call, :lhs, :count), lit(0)),
              # =>
              e(:lhs, :wont_be_empty))
  end

  def test_wont_equal__float
    assert_re(:RE_WONT_EQ_FLOAT,
              "_(obj).wont_be_close_to float_lit",
              weq(:lhs, s(:lit, 6.28)),
              # =>
              e(:lhs, :wont_be_close_to, s(:lit, 6.28)))
  end

  def test_wont_equal__hash
    assert_re(:RE_WONT_BE_EMPTY_LIT,
              "_(obj).wont_be_empty",
              weq(:lhs, s(:hash)),
              # =>
              e(:lhs, :wont_be_empty))
  end

  def test_wont_equal__length_0
    assert_re(:RE_WONT_SIZE_ZERO,
              "_(obj).wont_be_empty",
              weq(s(:call, :lhs, :length), lit(0)),
              # =>
              e(:lhs, :wont_be_empty))
  end

  def test_wont_equal__nil
    assert_re(:RE_WONT_EQ_NIL,
              "_(obj).wont_be_nil",
              weq(:lhs, s(:nil)),
              # =>
              e(:lhs, :wont_be_nil))
  end

  def test_wont_equal__oper
    assert_re(:RE_WONT_BE_OPER,
              "_(obj).wont_be :msg, val",
              weq(s(:call, :lhs, :msg, :rhs), s(:true)),
              # =>
              wbe(:lhs, :msg, :rhs))
  end

  def test_wont_equal__oper_f
    assert_re(:RE_WONT_BE_OPER_F,
              "_(obj).must_be :msg, val",
              weq(s(:call, :lhs, :msg, :rhs), s(:false)),
              # =>
              mbe(:lhs, :msg, :rhs))
  end

  def test_wont_equal__pred
    assert_re(:RE_WONT_BE_PRED,
              "_(obj).wont_be :pred?",
              weq(s(:call, :lhs, :pred?), s(:true)),
              # =>
              wbe(:lhs, :pred?))
  end

  def test_wont_equal__pred_f
    assert_re(:RE_WONT_BE_PRED_F,
              "_(obj).must_be :pred?",
              weq(s(:call, :lhs, :pred?), s(:false)),
              # =>
              mbe(:lhs, :pred?))
  end

  def test_wont_equal__size_0
    assert_re(:RE_WONT_SIZE_ZERO,
              "_(obj).wont_be_empty",
              weq(s(:call, :lhs, :size), lit(0)),
              # =>
              e(:lhs, :wont_be_empty))
  end

  # # TODO: make sure I'm picking up _ { ... }.must/wont...
  #
  # _(lhs.size).wont_be(:>, 0) -> must_be_empty
  # _(lhs.size).must_be(:>, 0) -> wont_be_empty
  # _(lhs.length).must_be(:>=, 4) # TODO: warn about magic numbers?
end

if __FILE__ == $0 then
  module Minitest
    $-w = nil
    def self.run(*); true; end
    $-w = true
  end

  class Symbol
    def sub re, s=nil, &b
      self.to_s.sub(re, s, &b).to_sym
    end
  end

  AssertScanner = MinitestLint::AssertScanner
  RE = AssertScanner::RE

  def ss re, str
    ->(ary) { ary.map { |s| s.sub(re, str) } }
  end

  out = ->(lbl, arr) {
    puts "# #{lbl}"
    puts arr.map { |s| "todo :#{s.to_s.delete_prefix "test_"}" }
    arr.empty?
  }

  a2r = ss(/assert/, "refute")
  r2a = ss(/refute/, "assert")
  m2w = ss(/must/,   "wont")
  w2m = ss(/wont/,   "must")

  at, rt, mt, wt =
    TestAssertScanner
    .instance_methods(false)
    .grep(/^test_/)
    .grep_v(/sanity/)
    .sort
    .group_by { |s| s[RE] }
    .values_at("assert", "refute", "must", "wont")

  m_rt = out[:MISSING_ASSERTS, r2a[rt - a2r[at]]]
  m_at = out[:MISSING_REFUTES, a2r[at - r2a[rt]]]
  m_wt = out[:MISSING_MUST,    w2m[wt - m2w[mt]]]
  m_mt = out[:MISSING_WONT,    m2w[mt - w2m[wt]]]

  clean = m_rt && m_at && m_wt && m_mt

  a, r = Minitest::Assertions
    .public_instance_methods
    .grep(/assert|refute/)
    .sort
    .partition { |s| s =~ /assert/ }

  m, w = Minitest::Expectations
    .public_instance_methods
    .grep(/must|wont/)
    .sort
    .partition { |s| s =~ /must/ }

  whitelist =
    %i{
       assert_mock
       assert_output assert_raises assert_send assert_silent assert_throws
       must_be_silent must_output must_raise must_throw
       must_be_within_delta must_be_within_epsilon
       wont_be_within_delta wont_be_within_epsilon
      }

  used = AssertScanner
    .__doco
    .to_a
    .flatten
    .map { |s| s[/(path_)?#{AssertScanner::RE}\w*/] }
    .compact
    .map(&:to_sym)
    .sort
    .uniq

  mi_a = out[:IMPL_ASSERT, a - used - whitelist]
  mi_r = out[:IMPL_REFUTE, r - used - whitelist]
  mi_m = out[:IMPL_MUST,   m - used - whitelist]
  mi_w = out[:IMPL_WONT,   w - used - whitelist]

  clean &&= mi_m && mi_r && mi_a && mi_w

  exit clean
end
