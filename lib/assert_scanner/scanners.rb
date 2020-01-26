class AssertScanner
  ORDER = %w{assert refute must wont}
  RE = Regexp.union(*ORDER) # TODO: rename?

  SCANNERS = {}

  ######################################################################
  # Doco Declarations:

  mc = (class << self; self; end)
  mc.attr_accessor :latest
  mc.attr_accessor :__doco

  self.latest = nil
  self.__doco = {}

  def self.doco from_to
    raise ArgumentError, "Already defined: #{from_to}" if
      from_to.keys.any? { |k| __doco.key? k }

    self.latest = from_to
    __doco.merge! from_to
  end

  def self.meta from_to
    self.latest = from_to
  end

  def self.latest_doco_to
    latest.values.first
  end

  ######################################################################
  # Pattern Declarations:

  def self.reset_scanners
    SCANNERS.clear
  end

  def self.register_assert *matchers, &handler
    raise "NO! %p" % [matchers] unless latest

    # TODO: register doco against the matcher so they can be looked up
    matchers.each do |matcher|
      if SCANNERS.key? matcher then
        warn "WARNING! Reassigning matcher! %p" % [matcher]
        warn "old: %s" % [SCANNERS[matcher].source_location]
        warn "new: %s" % [handler.source_location]
      end

      SCANNERS[matcher] = handler
    end

    self.latest = nil
  end

  def self.pattern patterns
    patterns.each do |name, value|
      const_set name, value
    end
  end

  def self.rewrite patterns, msg = latest_doco_to, &block
    self.pattern patterns

    register_assert(*patterns.values) do |exp|
      exp = self.instance_exec(exp, &block)
      change exp, msg if exp
    end
  end

  meta "old_assert(*args)" => "new_assert(*args)"
  def self.rename new_msg, patterns, msg = latest_doco_to
    rewrite patterns do |t, r, _m, *args|
      s(t, r, new_msg, *args)
    end
  end

  meta "old_assert obj.msg(*args)" => "new_assert obj, *args"
  def self.replace_call new_msg, patterns, msg = latest_doco_to
    rewrite patterns do |t, r, _m, (_, lhs, _, *rest)|
      s(t, r, new_msg, lhs, *rest)
    end
  end

  meta "old_assert obj.msg(*args)" => "new_assert obj, :msg, *args"
  def self.unpack_call new_msg, patterns, msg = latest_doco_to
    rewrite patterns do |t, r, _m, (_, recv, m, *rest)|
      s(t, r, new_msg, recv, s(:lit, m), *rest)
    end
  end

  meta "old_assert _expected, obj.msg(*args)" => "new_assert obj, :msg, *args"
  def self.unpack_and_drop new_msg, patterns, msg = latest_doco_to
    rewrite patterns do |t, r, _m, _lhs, (_, recv, m, *rest)|
      s(t, r, new_msg, recv, s(:lit, m), *rest)
    end
  end

  meta "old_assert _expected, obj" => "new_assert obj"
  def self.rename_and_drop new_msg, patterns, msg = latest_doco_to
    rewrite patterns do |t, r, _m, _lhs, rhs|
      s(t, r, new_msg, rhs)
    end
  end

  meta "assert lhs, rhs" => "assert rhs, lhs"
  def self.swap patterns, msg = latest_doco_to
    rewrite patterns do |t, r, m, lhs, rhs|
      s(t, r, m, rhs, lhs)
    end
  end

  meta "old_assert lhs.msg(rhs)" => "new_assert rhs, lhs"
  def self.replace_and_swap new_msg, patterns, msg = latest_doco_to
    rewrite patterns do |t, r, m, (_, lhs, _, rhs)|
      s(t, r, new_msg, rhs, lhs)
    end
  end

  ############################################################
  # Pattern Declaration Helpers:

  def self.parse str
    Sexp::Matcher.parse str
  end

  def self.pat *args
    parse "(call nil #{args.join " "})"
  end

  def self.assert_pat test
    pat :assert, test
  end

  def self.refute_pat test
    pat :refute, test
  end

  def self.eq_pat lhs, rhs
    pat :assert_equal, lhs, rhs
  end

  ############################################################
  # Pattern Helpers:

  def change exp, msg
    raise ArgumentError, "key already exists! %p in %p" % [exp, io] if io.key?(exp)
    io[exp] = msg
    self.count += 1
    exp
  end

  def handle_arity exp, arity
    exp, msg = exp[0..arity], exp[arity+1]

    change exp, "redundant message?" if msg if $v

    exp
  end

  ############################################################
  # Positive Assertions

  # TODO:
  # assert obj.is_a? klass
  # assert_raises Exception do ... end
  # assert_equal "str", klass.name
  # assert_cmp
  # assert_match
  # assert_raises
  # assert_respond_to
  # assert_same

  # This must be first, to remove the redundancies right off
  doco "assert obj, msg" => "assert obj"
  pattern RE_MSG: assert_pat("_ _")
  register_assert RE_MSG do |exp|
    handle_arity exp, 3
  end

  # This must be second, to flip to refute as soon as possible
  doco "assert ! obj" => "refute obj"
  replace_call(:refute,
               RE_NOT: assert_pat("(call _ !)"))

  doco "assert obj.empty?" => "assert_empty obj"
  replace_call(:assert_empty,
               RE_EMPTY: assert_pat("(call _ empty?)"))

  doco "assert exp == act" => "assert_equal exp, act"
  replace_call(:assert_equal,
               RE_EQUAL: assert_pat("(call _ == _)"))

  doco("assert_equal float_lit, act"    => "assert_in_epsilon float_lit, act",
       "assert_in_delta float_lit, act" => "assert_in_epsilon float_lit, act")
  rename(:assert_in_epsilon,
         RE_IN_EPSILON: pat(:assert_equal,    "(lit, [k Float])", "_"),
         RE_IN_DELTA:   pat(:assert_in_delta, "_",                "_"))

  doco "assert obj.instance_of? cls" => "assert_instance_of cls, obj"
  replace_and_swap(:assert_instance_of,
                   RE_INSTANCE_OF: assert_pat("(call _ instance_of? _)"))

  doco("assert obj.kind_of? mod" => "assert_kind_of mod, obj",
       "assert obj.is_a? mod"    => "assert_kind_of mod, obj")
  replace_and_swap(:assert_kind_of,
                   RE_KIND_OF: assert_pat("(call _ kind_of? _)"),
                   RE_IS_A:    assert_pat("(call _ is_a? _)"))

  doco "assert obj.include? val" => "assert_includes obj, val"
  replace_call(:assert_includes,
               RE_INCL: assert_pat("(call _ include? _)"))

  doco "assert obj.pred?" => "assert_predicate obj, :pred?"
  unpack_call(:assert_predicate,
              RE_PRED: assert_pat("(call _ _)"))

  doco "assert obj.msg(val)" => "assert_operator obj, :msg, val"
  unpack_call(:assert_operator,
              RE_OPER: assert_pat("(call _ _ _)"))

  doco "assert_equal exp, act" => "STOP"
  pattern RE_EQ_MSG: pat(:assert_equal, "_ _ _")
  register_assert RE_EQ_MSG do |exp|
    handle_arity exp, 4
  end

  doco "assert_equal nil, obj" => "assert_nil obj"
  rename_and_drop(:assert_nil,
                 RE_EQ_NIL: eq_pat("(:nil)", "_"))

  doco "assert_equal true, obj.pred?" => "assert_predicate obj, :pred?"
  unpack_and_drop(:assert_predicate,
                  RE_EQ_PRED: eq_pat("(true)",  "(call _ _)"))

  doco "assert_equal true, obj.msg(val)" => "assert_operator obj, :msg, val"
  unpack_and_drop(:assert_operator,
                  RE_EQ_OPER: eq_pat("(true)",  "(call _ _ _)"))

  doco "assert_equal 'long str', str" => "assert_includes str, 'substr'"
  rewrite(RE_EQ_LHS_STR: eq_pat("(str _)", "_")) do |t, r, _, (_, str), rhs, *|
    next unless str && str.length > 20

    s(t, r, :assert_includes, rhs, s(:str, str[0, 20]))
  end

  NOT_LAS = "[- [any (lit _) (str _) ([atom])]]" # LAS = lit, atom, str

  doco "assert_equal act, lit" => "assert_equal lit, act"
  swap(RE_EQ_RHS_LIT: eq_pat(NOT_LAS, "(lit _)"),
       RE_EQ_RHS_STR: eq_pat(NOT_LAS, "(str _)"),
       RE_EQ_RHS_NTF: eq_pat(NOT_LAS, "([atom])"))

  doco("assert_equal 0, obj.length" => "assert_empty obj",
       "assert_equal 0, obj.count"  => "assert_empty obj",
       "assert_equal 0, obj.size"   => "assert_empty obj")
  rewrite(RE_EQ_EMPTY: eq_pat("(lit 0)", "(call _ [m length size count])")) do |t, r, _, _, (_, recv, _)|
    s(t, r, :assert_empty, recv)
  end

  doco("assert_equal {}, obj" => "assert_empty obj",
       "assert_equal [], obj" => "assert_empty obj")
  rename_and_drop(:assert_empty,
                  RE_EQ_EMPTY_LIT: eq_pat("([m array hash])", "_"))

  doco "assert exp != act" => "refute_equal exp, act"
  replace_call(:refute_equal,
               RE_NEQUAL: assert_pat("(call _ != _)"))

  doco "assert_operator obj, :include?, val" => "assert_includes obj, val"
  rewrite(RE_OP_INCL: pat(:assert_operator, "_", "(lit include?)", "_")) do |t, r, _, obj, _, val|
    s(t, r, :assert_includes, obj, val)
  end

  doco "assert obj" => "WARNING"
  RE_PLAIN = assert_pat "_"
  register_assert RE_PLAIN do |exp|
    io[exp] = "Try to not use plain assert"
    nil
  end

  ############################################################
  # Negative Assertions

  # TODO:
  # refute_cmp
  # refute_match
  # refute_nil
  # assert(obj.size > 0) => refute_empty
  # lhs msg is count/length/size && rhs != 0 => refute_empty
  # lhs == binary call => refute_operator && rhs == false

  doco "refute obj, msg" => "refute obj"
  pattern RE_REF_MSG: refute_pat("_ _")
  register_assert RE_REF_MSG do |exp|
    handle_arity exp, 3
  end

  doco "refute ! obj" => "assert obj"
  replace_call(:assert,
               RE_REF_NOT: refute_pat("(call _ !)"))

  # TODO: normalize doco terms val/obj/etc
  doco "refute val.empty?" => "refute_empty val"
  replace_call(:refute_empty,
               RE_REF_EMPTY: refute_pat("(call _ empty?)"))

  doco "refute exp == act" => "refute_equal exp, act"
  replace_call(:refute_equal,
               RE_REF_EQUAL: refute_pat("(call _ == _)"))

  doco "refute exp != act" => "assert_equal exp, act"
  replace_call(:assert_equal,
               RE_REF_NEQUAL: refute_pat("(call _ != _)"))

  doco "refute obj.instance_of? cls" => "refute_instance_of cls, obj"
  replace_and_swap(:refute_instance_of,
                   RE_REF_INSTANCE_OF: refute_pat("(call _ instance_of? _)"))

  doco "refute obj.kind_of? mod" => "refute_kind_of mod, obj"
  replace_and_swap(:refute_kind_of,
                   RE_REF_KIND_OF: refute_pat("(call _ kind_of? _)"),
                   RE_REF_IS_A:    refute_pat("(call _ is_a? _)"))

  doco "refute obj.include? val" => "refute_includes obj, val"
  replace_call(:refute_includes,
               RE_REF_INCL: refute_pat("(call _ include? _)"))

  doco "refute obj.pred?" => "refute_predicate obj, :pred?"
  unpack_call(:refute_predicate,
              RE_REF_PRED: refute_pat("(call _ _)"))

  doco "refute obj.msg(val)" => "refute_operator obj, :msg, val"
  unpack_call(:refute_operator,
              RE_REF_OPER: refute_pat("(call _ _ _)"))

  doco "refute obj" => "WARNING"
  RE_REF_PLAIN = refute_pat "_"
  register_assert RE_REF_PLAIN do |exp|
    io[exp] = "Try to not use plain refute"
    nil
  end

  ############################################################
  # Expectations Helpers

  def self.exp_rewrite patterns, &block
    rewrite patterns do |sexp|
      self.instance_exec(match(sexp), &block)
    end
  end

  def self.must_pat lhs, msg, *rhs
    parse "(call (call nil :_ %s) %s %s)" % [lhs, msg, rhs.join(" ")]
  end

  def self.must_block_pat body, msg, rhs
    parse "(call (iter (call nil :_) 0 %s) %s %s)" % [body, msg, rhs]
  end

  def match exp
    _, (_, _, _, lhs), msg, *rhs = exp
    return lhs, msg, *rhs
  end

  def must lhs, msg, *rhs
    s(:call, s(:call, nil, :_, lhs), msg, *rhs)
  end

  ############################################################
  # Positive Expectations

  # TODO:
  # must_be
  # must_be_kind_of
  # must_equal
  # must_match
  # must_output
  # must_raise
  # must_respond_to
  # must_throw

  re_must_be_oper  = must_pat("(call _ _ _)",        :must_equal, "(:true)")
  re_wont_include  = must_pat("(call _ include? _)", :must_equal, "(:false)")
  re_must_be_empty = must_pat("(call _ [m length size count])", :must_equal, "(lit 0)")
  re_must_include  = must_pat("(call _ include? _)", :must_equal, "(:true)")
  re_must_be_empty_lit = must_pat("_",               :must_equal, "([m array hash])")
  re_must_be_pred  = must_pat("(call _ _)",          :must_equal, "(:true)")

  doco "_(obj).must_equal nil" => "_(obj).must_be_nil"
  exp_rewrite(RE_MUST_EQ_NIL: must_pat("_", :must_equal, "(:nil)")) do |lhs,|
    must lhs, :must_be_nil
  end

  doco "_(obj.include?(val)).must_equal true" => "_(obj).must_include val"
  exp_rewrite(RE_MUST_INCLUDE: re_must_include) do |(_, lhs, _, rhs),|
    must(lhs, :must_include, rhs)
  end

  doco "_(obj.length).must_equal 0" => "_(obj).must_be_empty"
  exp_rewrite(RE_MUST_BE_EMPTY: re_must_be_empty) do |(_, lhs, _), _, _|
    must(lhs, :must_be_empty)
  end

  doco "_(obj).must_equal([])" => "_(obj).must_be_empty"
  exp_rewrite(RE_MUST_BE_EMPTY_LIT: re_must_be_empty_lit) do |lhs,|
    must(lhs, :must_be_empty)
  end

  doco "_(obj.pred?).must_equal true" => "_(obj).must_be :pred?"
  exp_rewrite(RE_MUST_BE_PRED: re_must_be_pred) do |(_, lhs, msg),|
    must(lhs, :must_be, s(:lit, msg))
  end

  doco "_(obj.msg(val)).must_equal true" => "_(obj).must_be :msg, val"
  exp_rewrite(RE_MUST_BE_OPER: re_must_be_oper) do |(_, lhs, msg, rhs),|
    next if msg == :[]

    must(lhs, :must_be, s(:lit, msg), rhs)
  end

  doco "_(obj.include?(val)).must_equal false" => "_(obj).wont_include val"
  exp_rewrite(RE_WONT_INCLUDE: re_wont_include) do |(_, lhs, _, rhs),|
    must(lhs, :wont_include, rhs)
  end

  doco("_(obj).must_be(:instance_of?, cls)" => "_(obj).must_be_instance_of cls",
       "_(obj).must_be(:is_a?,        cls)" => "_(obj).must_be_instance_of cls")
  exp_rewrite(RE_MUST_BE_INSTANCE_OF: must_pat("_", :must_be, "(lit :instance_of?)", "_"),
              RE_MUST_BE_IS_A:        must_pat("_", :must_be, "(lit :is_a?)",        "_")) do |lhs, _, _, rhs|
    must(lhs, :must_be_instance_of, rhs)
  end

  doco "_(obj).must_be(:kind_of?, mod)" => "_(obj).must_be_kind_of mod"
  exp_rewrite(RE_MUST_BE_KIND_OF: must_pat("_", :must_be, "(lit kind_of?)", "_")) do |lhs, _, _, rhs|
    must(lhs, :must_be_kind_of, rhs)
  end

  doco "_(obj).must_be(:respond_to?, val)" => "_(obj).must_respond_to val"
  exp_rewrite(RE_MUST_BE_RESPOND_TO: must_pat("_", :must_be, "(lit respond_to?)", "_")) do |lhs, _, _, rhs|
    must(lhs, :must_respond_to, rhs)
  end

  ############################################################
  # Negative Expectations

  # TODO:
  # wont_be
  # wont_be_empty
  # wont_be_nil
  # wont_equal
  # wont_include
  # wont_match

  # TODO: move to positive

  re_wont_be_pred = must_pat("(call _ _)", :must_equal, "(:false)")
  re_wont_be_oper = must_pat("(call _ _ _)", :must_equal, "(:false)")

  doco "_(obj.pred?).must_equal false" => "_(obj).wont_be :pred?"
  exp_rewrite(RE_WONT_BE_PRED: re_wont_be_pred) do |(_, lhs, msg), _, _|
    must(lhs, :wont_be, s(:lit, msg))
  end

  doco "_(obj.msg(val)).must_equal false" => "_(obj).wont_be :msg, val"
  exp_rewrite(RE_WONT_BE_OPER: re_wont_be_oper) do |(_, lhs, msg, rhs),|
    next if msg == :[]

    must(lhs, :wont_be, s(:lit, msg), rhs)
  end

  ############################################################
  # Structural transformations (or stopping points)

  # TODO: arg vs no arg?
  re_must_other = parse("(call (call nil [m expect value] _) [m /^must/] _)")

  # TODO: arg vs no arg?
  doco("_(obj).must_<something> val" => "STOP",
       "_(obj).must_<something>"     => "STOP")
  rewrite(RE_MUST_GOOD: must_pat("_", "[m /^must/]", "_")) do
    # STOP
  end

  # TODO: arg vs no arg?
  doco("_{ ... }.must_<something> val" => "STOP",
       "_{ ... }.must_<something>"     => "STOP")
  rewrite(RE_MUST_BLOCK_GOOD: must_block_pat("___", "[m /^must/]", "_")) do
    # STOP
  end

  doco("expect(obj).must_<something> val" => "_(obj).must_<something> val",
       "value(obj).must_<something> val"  => "_(obj).must_<something> val",
       "expect(obj).must_<something>"     => "_(obj).must_<something>",
       "value(obj).must_<something>"      => "_(obj).must_<something>")
  exp_rewrite(RE_MUST_OTHER: re_must_other) do |lhs, msg, rhs|
    must lhs, msg, rhs
  end

  # TODO: arg vs no arg?
  doco("obj.must_<something> val" => "_(obj).must_<something> val",
       "obj.must_<something>"     => "_(obj).must_<something>")
  rewrite(RE_MUST_PLAIN: parse("(call _ [m /^must/] _)")) do |t, lhs, msg, rhs|
    must lhs, msg, rhs
  end
end