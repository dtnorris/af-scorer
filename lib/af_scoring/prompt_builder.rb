# frozen_string_literal: true

module AFScoring
  class PromptBuilder
    SYSTEM_INSTRUCTIONS = <<~TEXT.freeze
      You are an AdventureFinder production assessment scorer.

      Apply the supplied AFAO rubric and AdventureFinder Analysis Data / Assessment Specification exactly.
      Score only the canonical Adventure ID named in the request. Do not silently score a containing book,
      parent campaign, nested child, adjacent adventure, or general reputation of the product.

      Base every judgment on the supplied published source material and substantially-as-published play.
      Keep dimensions analytically independent. Choose the best-supported permitted value; do not drift toward
      the middle because confidence is low. Perform adjacent-anchor falsification for every interpretive score.

      Do not use prior AdventureFinder scores for the target. If target-specific benchmark information appears
      accidentally in the material, ignore it and report the contamination in group_observations.notes.

      Return only data conforming to the provided response schema. Do not omit required fields and do not invent
      evidence locators that are not present in the supplied source.
    TEXT

    INTERPRETIVE_CONFIDENCE_GUIDANCE = <<~TEXT.freeze
      # Interpretive Confidence Semantics

      For every scored interpretive dimension, confidence is an integer from 0 through 100
      representing confidence that the assigned rubric value is the best-supported permitted
      value given the supplied published evidence and rubric. It is not confidence that the
      source exists, confidence in the model generally, the probability that every factual
      statement is correct, a substitute for rubric_ambiguity or evidence_sufficient, or a
      measure of score magnitude.

      A confidence of 0 means essentially no confidence that the assigned score is supportable.
      Low values correspond to weak or uncertain support; high values correspond to strong
      evidence and clear separation from adjacent anchors. When evidence_sufficient is true,
      the response supplies substantive evidence and clear adjacent-anchor falsification, and
      rubric_ambiguity is false, confidence 0 is exceptional and must be explained by the
      rationale rather than used as a schema-filling default.

      Confidence does not control the score. Choose the best-supported rubric value first;
      never move the score toward the middle because confidence is low.
    TEXT

    # # of Sessions intentionally uses a dedicated blind-assessment profile rather
    # than the general production prompt stack. This is the canonical NoS prompt.
    NOS_SYSTEM_INSTRUCTIONS = <<~TEXT.freeze
      You are performing an independent blind AdventureFinder # of Sessions assessment.

      Assess only the canonical adventure supplied in the request, using only its supplied
      canonical published source material and the frozen AdventureFinder # of Sessions rubric.

      Do not search for, infer, or use any prior AdventureFinder score, benchmark placement,
      calibration result, model result, expected value, endpoint role, or prior discussion
      of this adventure.

      Estimate # of Sessions independently from the published material and frozen rubric.
      Do not assess or infer scores for other AdventureFinder dimensions.

      Return only data conforming to the provided response schema. Do not omit required fields
      and do not invent evidence locators that are not present in the supplied source.
    TEXT

    # Exploration Emphasis uses the exact locally qualified v0.5 blind-assessment
    # profile. Keep this scorer-facing string byte-for-byte stable unless EE is
    # explicitly requalified; it does not inherit the general production assessment
    # specification or accumulated production guardrail stack.
    EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5 = <<~TEXT.freeze
      You are performing an independent blind AdventureFinder Exploration Emphasis assessment.

      Assess only the canonical adventure supplied in the request, using only its supplied
      canonical published source material and the frozen AdventureFinder Exploration Emphasis rubric.

      Do not search for, infer, or use any prior AdventureFinder score, benchmark placement,
      calibration result, model result, expected value, endpoint role, or prior discussion
      of this adventure.

      Assess Exploration Emphasis independently from the published material and frozen rubric.
      Do not assess or infer scores for other AdventureFinder dimensions.

      # Exploration Emphasis Operational Clarification v0.5

      Apply the complete frozen Exploration Emphasis rubric supplied in the request. This
      clarification does not change its definition or anchors.

      Judge expected substantive table play and the structural role of environmental
      engagement, not the raw number of locations, rooms, routes, traps, hazards, locks,
      terrain effects, travel segments, or other environmental features.

      Environmental features are not automatically exploration play. An environmental
      feature counts toward Exploration Emphasis when ordinary play requires substantive
      discovering, interpreting, navigating, traversing, testing, or materially interacting
      with the environment itself. Do not accumulate many discrete rooms, obstacles, checks,
      defenses, or movement steps into a higher Exploration score merely because they occur
      in physical space.

      Use a substantive-progression test, not a necessity test. Environmental play supports
      a higher Exploration score when engaging with the environment itself forms a
      substantial body of ordinary play: players repeatedly discover, interpret, choose
      among, navigate, traverse, test, or manipulate environmental states or routes, and
      those activities materially shape how progression unfolds.

      Do not infer dominance merely because environmental steps are required to reach or
      execute objectives. A prescribed route, travel leg, tracking procedure, keyed-room
      sequence, locked passage, trap sequence, or repeated check can be necessary for
      progression while remaining instrumental to separately authored objectives,
      encounters, or revelations. Necessity, recurrence, and gating are not by themselves
      evidence of Score 4.

      Use a compression counterfactual when the distinction is unclear. Ask what substantive
      play would remain if the environmental access procedure were compressed while
      preserving the destinations, encounters, revelations, and mission objectives. If most
      of the adventure's substantive progression structure would remain, environmental play
      is more likely supporting or secondary. If compression would remove or radically
      restructure major bodies of ordinary play because discovering, navigating, traversing,
      or interacting with the environment is itself a major activity, that supports High or
      Dominant Exploration.

      Apply that counterfactual to environmental access or connective procedure, not to erase
      environment-centered challenges themselves. If a trap, puzzle, investigation, combat
      situation, or other challenge derives its substantive play from discovering,
      interpreting, navigating, traversing, or manipulating the environment, compressing
      that environmental activity would remove part of the challenge rather than merely
      shorten access to it.

      AdventureFinder dimensions are analytically independent but are not mutually
      exclusive. Do not subtract from Exploration Emphasis merely because the same play
      also constitutes Puzzle / Problem-Solving, Investigation, Combat, or mission
      execution. When discovering, interpreting, navigating, traversing, or manipulating
      the environment is itself part of the substantive activity, that environmental
      component counts toward Exploration Emphasis even when another dimension also applies.

      Likewise, the presence of another mode should weigh against a higher Exploration
      score only to the extent that the other mode carries substantial progression outside
      the environmental structure. Combat, puzzles, investigation, or social interaction
      that occur primarily within, are triggered by, or are enabled by sustained
      environmental engagement do not automatically displace Exploration as a dominant mode.

      Do not lower Exploration Emphasis because a site is compact, linear, bounded, or has
      few locations. Structural Openness and geographic scale are separate.
      A compact or linear site can still have high Exploration Emphasis when sustained
      environmental play itself regularly drives progress.

      For the 1 <-> 2 boundary, movement among several rooms, interaction with environmental
      props, or incidental hazards does not by itself establish Low Exploration. Score 2
      requires a bounded but meaningful body of environmental play that is more than
      backdrop or connective movement.

      For the 2 <-> 3 boundary, do not promote Low to Mixed merely by accumulating discrete
      environmental features or sequential obstacles. Score 3 requires environmental play
      to form a substantial recurring or sustained mode of expected play alongside
      comparably important non-exploration progression. Score 3 can include recurring
      environmental activity that repeatedly enables or connects distinct objectives;
      recurrence or necessity alone does not promote it to Score 4.

      For the 3 <-> 4 boundary, Score 4 requires environmental engagement itself to form
      one of the adventure's major bodies of ordinary substantive play and to regularly
      carry progress. It does not require Exploration to dominate the overall narrative,
      every chapter, or every other mode, and no single environmental discovery or
      traversal must drive the entire adventure. Combat, investigation, social interaction,
      or other modes may be equally important without falsifying Score 4.

      Once environmental engagement satisfies that positive Score 4 test, the existence of
      comparably important combat, investigation, social interaction, puzzles, or other
      modes is not a reason to demote the adventure to Score 3. Score 3 is not the default
      whenever several major modes coexist. The 3 <-> 4 distinction is whether Exploration
      itself is one of the dominant bodies of play, not whether it exceeds the others.

      To hold at Score 3 rather than Score 4, identify why the recurring environmental
      activity principally functions as access, transition, gating, or implementation for
      separately structured objectives, or why it remains substantial without itself
      forming one of the adventure's dominant bodies of play. To assign Score 4, identify
      recurring major segments in which environmental discovery, navigation, traversal, or
      interaction is itself a core substantive activity rather than merely a required step
      on the way to another objective.

      For the 4 <-> 5 boundary, Score 5 does not require the absence of combat, puzzles,
      investigation, or other modes. It requires the adventure to be fundamentally
      organized around environmental discovery, navigation, traversal, or interaction,
      with other substantive modes largely occurring within or being enabled by that
      environmental structure.

      Treat Dominant as an organizational test, not an exclusivity or majority-of-table-time
      test. Frequent, difficult, or important combat, puzzles, or investigation do not by
      themselves hold an adventure at Score 4 when those modes predominantly occur as
      contents, consequences, or expressions of exploring the same site, region, or
      environment. To hold at Score 4 rather than Score 5, identify a substantial major
      progression structure that remains organizationally independent of environmental
      exploration; do not rely only on the presence or importance of overlapping modes.

      Return only data conforming to the provided response schema. Do not omit required fields
      and do not invent evidence locators that are not present in the supplied source.
    TEXT

    # GM Beginner Suitability intentionally uses a dedicated blind-assessment
    # profile for reset-era local qualification. It does not inherit the
    # accumulated production GMBS guardrail stack.
    GMBS_SYSTEM_INSTRUCTIONS = <<~TEXT.freeze
      You are performing an independent blind AdventureFinder GM Beginner Suitability assessment.

      Assess only the canonical adventure supplied in the request, using only its supplied
      canonical published source material and the frozen AdventureFinder GM Beginner Suitability rubric.

      Do not search for, infer, or use any prior AdventureFinder score, benchmark placement,
      calibration result, model result, expected value, endpoint role, or prior discussion
      of this adventure.

      Assess GM Beginner Suitability independently from the published material and frozen rubric.
      Do not assess or infer scores for other AdventureFinder dimensions.

      # GMBS Operational-Support Clarification v0.3

      Assess GM Beginner Suitability by judging how well the published adventure supports
      a GM with little or no prior GM experience in actually running this adventure.

      Judge support supplied by the publication itself. Do not give credit for missing
      guidance merely because an experienced GM could infer, invent, or supply it easily.

      Do not treat a responsibility as unsupported merely because the GM must still perform
      it. Judgment, presentation, NPC portrayal, tactics, adjudication, and ordinary
      improvisation can occur within a well-supported published operating structure.


      For the 1 <-> 2 boundary:

      - Score 1 does not require a complete absence of useful guidance.

      - A clear premise, objectives, sequence of events, encounter descriptions, or ending
        do not by themselves establish score 2. Conceptual structure is not the same as
        executable operating support.

      - Evaluate executable progression at the scale at which the adventure organizes
        ordinary play. A substantial authored progression can be sequential, state-based,
        or composed of an explorable set or network of individually executable locations,
        encounters, or situations. It does not require a separate whole-adventure
        flowchart, pacing system, tracker, or state-management layer.

      - Individually executable situations count only when they collectively constitute a
        substantial body of ordinary expected play and the publication supplies a usable
        way for play to progress among or through them. Isolated runnable encounters do
        not by themselves establish score 2.

      - Favor score 1 when important ordinary play still requires the GM to supply the
        substantive operating middle: important triggers, transitions, reactions,
        procedures, changing conditions, consequences, or other structures needed to make
        a substantial body of central expected play runnable. Do not infer that this
        operating middle is missing merely because there is no separate global management
        layer above otherwise executable published situations.

      - Favor score 2 when the publication carries a substantial body of ordinary play
        through an authored executable progression or functioning runtime/state mechanism,
        including when that progression is composed of individually executable situations
        connected by the adventure's published structure, even though recurring support
        gaps remain and prior GM experience still helps.

      - Boundary test:
        Ask whether the publication authors enough of the actual situations and transitions
        that constitute ordinary play for an inexperienced GM to run a substantial body of
        it. If the text mainly establishes WHAT should happen while the GM must construct
        important parts of HOW those situations operate or connect, favor 1. If it supplies
        a usable operating structure for that central play, even without separate global
        management aids, but leaves recurring gaps, favor 2.


      For the 2 <-> 3 boundary:

      - Score 3 does not require flowcharts, trackers, formal pacing systems, comprehensive
        contingency systems, explicit recovery procedures, or a separate whole-adventure
        management layer.

      - When ordinary play is organized through sites, rooms, encounters, or other discrete
        situations, do not discount substantial executable area-by-area support merely
        because the publication lacks an additional overarching management system. The
        published situations and their connections can themselves constitute the governing
        structure of ordinary play.

      - Favor score 2 when recurring important situations or transitions remain materially
        under-authored, so prior GM experience must repeatedly supply substantive operating
        structure across expected play.

      - Favor score 3 when the publication authors the governing structure of ordinary play
        well enough that expected situations and important procedures are substantially
        executable from the text, including when that governing structure is a published
        site, location, encounter, or situation network rather than a separate global system.

      - Remaining judgment, presentation, negotiation, tactics, connective execution, or
        ordinary improvisation do not by themselves prevent score 3.

      - Distinguish 2 from 3 by the importance of missing authored operating structure, not
        by whether the publication supplies dedicated whole-adventure management tools.


      For the 4 <-> 5 boundary:

      - Score 5 requires strong novice-GM scaffolding beyond clear organization,
        abundant detail, or strong runnability.

      - Judge that scaffolding by its instructional FUNCTION, not by whether it takes an
        explicitly didactic form. Score 5 does not require teaching general GMing as a
        craft, explaining design theory, or presenting advice applicable to unrelated
        adventures.

      - Support can have instructional function when the adventure's operating structure
        guides an inexperienced GM through HOW and WHEN to perform important responsibilities
        in practice: for example by sequencing decisions, cueing when procedures apply,
        externalizing changing state, supplying recurring prompts or examples, providing
        fallback logic, or showing how to respond to likely developments.

      - Scaffolding may be broad and recurring across the adventure or concentrated
        around important adventure-specific systems or responsibilities.

      - A procedure is not exceptional scaffolding merely because it is clear, detailed, or
        directly usable. Simply stating what happens, what rule applies, or what steps the GM
        should perform can make an adventure highly runnable without establishing score 5.

      - Do not treat residual complexity as evidence against score 5 by itself. Branching,
        interacting NPCs or factions, state tracking, atmosphere, judgment, cognitive load,
        or other difficult GM responsibilities may remain when the publication exceptionally
        scaffolds an inexperienced GM in handling them.

      - Score 5 does not require eliminating all novice difficulty, scripting every choice,
        making the adventure simple, or removing ordinary GM judgment.

      - Favor score 4 when the publication makes the adventure highly runnable but its
        support is primarily organizational, documentary, or directly procedural, leaving
        the inexperienced GM to substantially determine how to coordinate or operationalize
        important difficult responsibilities.

      - Favor score 5 when the publication repeatedly scaffolds the inexperienced GM through
        performing important responsibilities: what to attend to, when and how to act, and
        how to handle likely developments. Difficult responsibilities can remain, provided
        the publication itself makes their operation exceptionally learnable and actionable
        for a novice GM.

      - Boundary test:
        Do not ask only how MUCH support exists or how complex the adventure remains. Ask
        whether the support mainly documents executable content, favoring 4, or whether it
        also structures the novice GM's performance of important responsibilities in
        practice, favoring 5.


      Keep GM Beginner Suitability independent from adventure harshness.

      Do not lower the score merely because the adventure is lethal, unforgiving, permits
      severe failure, or lacks a recovery path after catastrophic player failure. These
      features matter only when they create an actual GM-facing operating responsibility
      that the publication expects the GM to handle but does not adequately support.

      Return only data conforming to the provided response schema. Do not omit required fields
      and do not invent evidence locators that are not present in the supplied source.
    TEXT

    EXPERIMENTAL_COMBAT_GUARDRAIL_V0_7 = <<~TEXT.freeze
      # Combat Emphasis Application Guardrail

      When assessing Combat Emphasis, evaluate the role of combat across the expected
      substantive table play of the entire canonical adventure.

      Do not infer Combat Emphasis mechanically from encounter count, hostile-creature
      density, the presence of multiple combat-ready locations, the violence of the
      premise, encounter difficulty, or the importance of particular fights. These
      features may be evidence, but none is sufficient by itself to establish a high
      Combat Emphasis score.

      Weight optional, bypassable, negotiable, avoidable, and path-dependent combats
      according to their expected presence in substantially-as-published play. A
      supported combat-forward route does not by itself establish the Combat Emphasis
      of ordinary expected play.

      For the 1 ↔ 2 boundary:
      - Score 1 when combat may recur, matter, and carry consequences but remains
        structurally substitutable as a mode of canonical progression: the adventure
        supports its substantive progression through other modes without active hostile
        opposition becoming a materially embedded part of ordinary completion.
      - Score 2 when combat remains clearly secondary but active hostile opposition is
        structurally embedded as a genuine mode of canonical progression: ordinary
        completion includes materially consequential hostile resistance that must be
        overcome, survived, escaped, driven off, or otherwise resolved rather than being
        systematically replaceable by authored noncombat alternatives.
      - When distinguishing score 1 from score 2, do not treat recurrence,
        consequence, likelihood, rarity, concentration, or the presence or absence of
        repeated mandatory fights as sufficient evidence in either direction. Assess
        whether active hostile opposition remains structurally substitutable across
        ordinary canonical progression or is instead embedded as a genuine secondary
        mode of that progression.
      - Score 1 remains appropriate when combat can recur or become consequential but
        authored noncombat alternatives systematically preserve substantive canonical
        progression without active hostile opposition becoming materially embedded in
        ordinary completion. Recurring hostile creatures, a supported fight-through
        route, or combat that is likely to occur somewhere in ordinary play do not by
        themselves establish score 2.
      - Score 2 remains appropriate when active hostile opposition is structurally
        embedded in ordinary canonical progression even if combat is infrequent,
        concentrated, or occupies a small share of expected play. Score 2 does not
        require combat throughout most of the adventure, a large share of table time,
        repeated mandatory battles, or killing opponents. Do not use the presence of a
        single mandatory fight as a standalone test for score 2.

      For the 2 ↔ 3 boundary:
      - Score 2 when combat occurs and matters but remains clearly secondary across the
        canonical adventure.
      - Score 3 when combat functions as a substantial recurring component across
        ordinary canonical play alongside comparably important noncombat modes.
      - Consequential or repeated combat does not by itself establish score 3 when it
        is concentrated, strongly path-dependent, or largely confined to a phase or
        climax.
      - When combat is materially concentrated within a phase, do not treat that
        concentration as sufficient evidence either for score 2 or against score 3.
        Assess the structural role of the combat-bearing phase in ordinary canonical
        progression: whether it is itself a substantial operational body of that
        progression, and whether active hostile opposition repeatedly carries or gates
        progress through that body.
      - Score 3 can be supported despite geographic or narrative concentration when
        the combat-bearing phase is itself a substantial operational body of ordinary
        canonical progression and active hostile opposition repeatedly functions as
        progress-bearing play through it. The phase being merely decisive, central, or
        combat-heavy is not sufficient.
      - Score 2 remains appropriate when repeated hostile play principally occupies a
        bounded, route-dependent, terminal, or otherwise secondary resolution layer
        within progression substantially carried elsewhere by other modes. Do not
        assign score 2 merely because most combat occurs within one identifiable phase.
      - Do not accumulate mutually exclusive combat paths, endings, or encounter
        branches as though they all occur in one ordinary playthrough. Weight them
        according to their expected presence in substantially-as-published play.

      For the 3 ↔ 4 boundary:
      - Score 3 when combat is a substantial recurring component but comparably
        important noncombat modes also carry meaningful portions of progression.
      - Score 4 only when combat is genuinely one of the adventure's dominant modes
        across the canonical unit and regularly drives progress.
      - Several mandatory combats, a combat-heavy act or dungeon, or an important
        combat climax do not by themselves establish score 4 if combat remains
        concentrated or shares progression with comparably structural noncombat play.

      For the 4 ↔ 5 boundary:
      - Score 4 when combat is highly prominent and regularly progress-bearing but
        major canonical progression is also substantially organized by noncombat
        structures that carry progression independently of combat.
      - Score 5 when fighting or overcoming combat opposition is itself a
        fundamental organizing structure of expected progression across the canonical
        adventure.
      - When distinguishing score 4 from score 5, do not treat the mere presence of
        substantial noncombat activity as sufficient evidence for score 4, and do not
        require combat to be the sole or exclusive organizer of progression for score
        5. Assess whether the cited noncombat structures independently carry major
        canonical progression or instead principally operate within, connect, locate,
        modify, intensify, or resolve progression fundamentally organized around
        overcoming combat opposition.
      - Score 4 remains appropriate when major noncombat structures genuinely carry
        progression independently of combat rather than principally serving an
        encounter-organized progression. Their significance must be structural, not
        merely the presence of exploration, traversal, environmental hazards, mission
        objectives, logistics, investigation, social interaction, or escape play.
      - Score 5 remains appropriate when fighting or overcoming combat opposition is a
        fundamental organizing structure of expected progression even though
        significant noncombat play also occurs. "Fundamentally organized around
        combat" does not mean "organized exclusively around combat." Score 5 does not
        require combat in every scene, every hostile encounter to be resolved by
        fighting, or the absence of significant noncombat play.
      - Optional, bypassable, negotiable, or avoidable encounters do not by
        themselves prevent score 5 when the expected progression of the canonical
        adventure remains fundamentally organized around overcoming combat
        opposition.
      - The fact that removing most combat would substantially change the adventure
        is supporting evidence for score 5, not a sufficient standalone test.
        Important combats can be indispensable to an adventure without combat being
        its fundamental organizing mode.

      Adjacent-anchor falsification for Combat Emphasis must be structural:
      - When distinguishing score 1 from score 2, explicitly test both adjacent
        interpretations before assigning either score. Determine whether active hostile
        opposition remains structurally substitutable across ordinary canonical
        progression or is instead embedded as a genuine secondary mode of that
        progression. To assign 1, explain how authored noncombat alternatives
        systematically preserve substantive progression without hostile opposition
        becoming materially embedded in ordinary completion. To assign 2, explain why
        that substitutability fails and how hostile resistance is structurally embedded
        even if combat is infrequent or concentrated. Recurrence, consequence,
        frequency, rarity, or a single mandatory fight must not resolve the boundary in
        either direction.
      - When distinguishing score 2 from score 3, explicitly test both adjacent
        interpretations before assigning either score. If combat is materially
        concentrated within a phase, determine whether that phase is itself a
        substantial operational body of ordinary canonical progression and whether
        active hostile opposition repeatedly carries or gates progress through it.
        To assign 3, explain why those conditions make combat a substantial recurring
        component rather than merely consequential concentrated play. To assign 2,
        explain why they are not satisfied and why the hostile play instead remains
        principally a bounded, route-dependent, terminal, or otherwise secondary
        resolution layer. Phase concentration alone must not resolve the boundary in
        either direction.
      - Before assigning 4, identify why the adventure exceeds 3 rather than merely
        containing substantial recurring combat alongside comparably important
        noncombat play.
      - When distinguishing score 4 from score 5, explicitly test both adjacent
        interpretations before assigning either score. Determine whether substantial
        noncombat structures independently carry major canonical progression or
        principally operate within, connect, locate, modify, intensify, or resolve
        progression fundamentally organized around overcoming combat opposition. To
        assign 4, identify the major independently progress-bearing noncombat
        structure rather than relying on the mere presence of significant noncombat
        activity. To assign 5, explain why the cited noncombat activity does not supply
        a coequal independent progression structure and why overcoming combat
        opposition remains a fundamental organizer. Neither "combat is not the sole
        organizer" nor "significant noncombat play exists" may resolve the boundary in
        either direction.


      Do not presume that a lower Combat Emphasis score is preferable. Assign 4 or 5
      whenever the whole-adventure evidence satisfies those anchors.
    TEXT

    # v0.7 remains frozen above as the calibration control. v0.7.1 is the
    # production Combat Emphasis prompt profile.
    COMBAT_GUARDRAIL_V0_7_1 = (
      EXPERIMENTAL_COMBAT_GUARDRAIL_V0_7 + <<~TEXT

        # Combat-Mode Accounting Clarification

        Throughout the boundary tests above, references to "active hostile opposition",
        "hostile resistance", or "overcoming combat opposition" count toward Combat
        Emphasis only to the extent ordinary expected play realizes them as a
        combat-bearing confrontation. A hostile creature, defended location, or
        dangerous opponent is not combat merely because it can be fought or because
        progression must somehow deal with it.

        Fighting, surviving an imposed attack, or escaping while under active attack
        may count as combat-bearing play. Negotiation, bargaining, intimidation,
        compliance, stealth, avoidance, bypass, or another authored noncombat
        resolution before an active confrontation occurs must be weighted as noncombat
        play, not credited to Combat Emphasis merely because the same opponent could
        have been fought.

        Do not use "hostile opposition must be resolved somehow" as a proxy for combat.
      TEXT
    ).freeze

    INVESTIGATION_EMPHASIS_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Investigation Emphasis Application Guardrail v0.1

      Apply the frozen AFAO Investigation Emphasis definition to the substantive
      player-facing inquiry the adventure requires, not to the difficulty or
      obscurity of its clues.

      # Directness Is Not a Disqualifier

      Investigation does not require ambiguous evidence, competing hypotheses,
      multiple independent sources, prolonged deduction, or difficult inference.
      Direct, explicit, or readily usable evidence can still support Investigation
      when players must meaningfully seek, gather, connect, interpret, or test that
      information to determine facts, causes, identities, relationships, or
      explanations.

      Conversely, passive exposition, a briefing, or an isolated interaction that
      simply supplies an answer without substantive player inquiry does not become
      Investigation merely because the characters learn information. Do not turn
      "easy to understand" into evidence against Investigation, and do not turn
      "information is present" into evidence for it.

      # Aggregate Recurrence and Causal Structure Across the Canonical Unit

      For the 2 ↔ 3 boundary, aggregate qualifying inquiry across the whole canonical
      adventure. A sequence of individually straightforward investigations in
      different phases can collectively form a substantial recurring mode. Do not
      score each inquiry only by its local complexity and then cap the whole adventure
      at 2 because no single clue chain is difficult or prolonged.

      For the 3 ↔ 4 ↔ 5 boundaries, assess how Investigation drives and organizes
      progression, not merely what fraction of table time visibly consists of clue
      gathering. Combat, exploration, infiltration, social interaction, travel, or a
      confrontation does not automatically dilute Investigation when that downstream
      play occurs because inquiry revealed the next actor, objective, location,
      relationship, cause, or materially revised understanding of the problem.

      Distinguish the upper anchors structurally:
      - Score 3 when Investigation is a substantial recurring mode but major
        progression is still comparably carried by other modes independently of the
        investigative chain.
      - Score 4 when Investigation is one of the dominant modes and its findings
        regularly drive major progress through the adventure.
      - Score 5 when the repeated discovery -> revised understanding -> next actionable
        objective, actor, or location cycle is itself a fundamental organizing
        structure of expected progression, even though substantial combat,
        exploration, infiltration, or social play occurs within the resulting phases.

      Do not inflate upper scores merely because one clue unlocks the next scene or
      because every phase has some information in it. The cited inquiry must have the
      recurring progress-driving or organizing role required by the frozen anchor.

      # Classify by Epistemic Purpose, Not by the Presence of Clues

      Ask what question the player-facing reasoning is principally answering.
      Determining what happened, what is happening, why it happened, who is
      responsible, what relationship exists, or what explanation is true supports
      Investigation. Determining how to traverse a route, operate or bypass a
      mechanism, use a key, decode operational instructions, defeat a trap, or solve
      an explicit obstacle is principally Puzzle / Problem-Solving, Exploration, or
      another relevant mode unless it also establishes qualifying facts, causes,
      identities, relationships, or explanations.

      Cryptic wording, coded hints, route clues, mechanism instructions, and
      environmental trial-and-error do not become Investigation merely because they
      require interpretation.

      In adjacent-anchor falsification, explicitly test the relevant structural
      distinction: localized inquiry versus recurring inquiry for 2 ↔ 3; recurring
      inquiry versus regular progress-driving inquiry for 3 ↔ 4; and regular
      progress-driving inquiry versus investigation as a fundamental organizer for
      4 ↔ 5. Clue difficulty, clue directness, or the presence of downstream non-
      investigation scenes must not resolve those boundaries by proxy.

      This guardrail clarifies application of the frozen AFAO rubric. It does not
      alter the anchors, create benchmark-specific rules, or presume that a higher or
      lower Investigation Emphasis score is preferable.
    TEXT

    # v0.3 deliberately branches from the successful v0.1 control. The rejected
    # v0.2 experiment is not inherited. This pass adds only an upper-anchor decision
    # audit for 3 ↔ 4 and 4 ↔ 5.
    INVESTIGATION_EMPHASIS_GUARDRAIL_V0_3 = (
      INVESTIGATION_EMPHASIS_GUARDRAIL_V0_1 + <<~TEXT

        # Investigation Emphasis Upper-Anchor Decision Isolation v0.3

        Apply this clarification only to the 3 ↔ 4 and 4 ↔ 5 boundaries. Do not use it
        to alter the v0.1 treatment of Minimal, Low, or the 2 ↔ 3 recurrence boundary.

        # Decide 3 ↔ 4 Before Testing 4 ↔ 5

        Evaluate 3 ↔ 4 on its own terms before asking whether score 5 is satisfied.
        Absence of a score-5 property is not evidence for score 3. In particular, do
        not reject 4 because Investigation is not the sole or fundamental organizer,
        because every major phase does not continue an investigative chain, or because
        the adventure eventually shifts into confrontation, escape, survival, or
        another terminal resolution mode.

        To assign 3 rather than 4, identify the substantive major progression that
        other modes carry independently of the investigative chain across ordinary
        expected play. The mere presence of substantial combat, exploration,
        infiltration, social interaction, or a non-investigative climax does not by
        itself establish that independent progression.

        To assign 4, establish positively that Investigation is one of the adventure's
        dominant modes and that its findings regularly drive major progress. Score 4
        does not require the repeated discovery -> revised understanding -> next major
        objective cycle to be a fundamental organizer; that additional requirement
        belongs only to the 4 ↔ 5 decision.

        # Independent-Spine Audit — 4 ↔ 5

        Only after score 4 is satisfied, test whether another authored major-objective
        spine substantially determines the sequence of major actors, locations,
        objectives, or problem states independently of investigative discoveries.

        Score 4 is supported when such an independent spine materially carries major
        progression even though Investigation repeatedly informs, unlocks, or modifies
        it. Score 5 is supported when repeated investigative discoveries themselves
        materially revise what the problem is and determine which major actor,
        location, objective, or problem state becomes actionable next, such that no
        comparable independent authored spine substantially specifies that sequence.

        Judge the lineage between major phases, not merely the local play mode inside
        each phase. Combat, exploration, infiltration, or social interaction within a
        major phase does not by itself make that phase structurally independent when
        investigative discovery is what made that phase the next major objective.

        One clue leading to one scene or location is insufficient for score 5. The
        investigation-organized pattern must recur across major phases. Conversely,
        once repeated investigative discoveries have organized that progression, the
        final discovered objective may resolve through confrontation, escape, survival,
        or another terminal mode without needing to generate one more investigation.

        In adjacent-anchor falsification, record the decisions in sequence: first name
        the independent progression structure that keeps the adventure at 3, or explain
        why Investigation regularly drives enough major progress to establish 4; then,
        only if 4 is established, identify the independent major-objective spine that
        keeps the adventure at 4, or explain why recurring investigative discoveries
        themselves organize the major-objective sequence strongly enough for 5.

        This is a decision-order clarification, not a direction to prefer higher
        scores. Preserve 3 or 4 whenever the required independent progression structure
        is actually present in substantially-as-published play.
      TEXT
    ).freeze

    PUZZLE_PROBLEM_SOLVING_EMPHASIS_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Puzzle / Problem-Solving Emphasis 1 ↔ 2 Boundary Guardrail v0.1

      Apply this clarification only to the 1 ↔ 2 boundary. It does not modify the
      2 ↔ 3 or upper boundaries and does not presume that either boundary score is
      preferable.

      # Qualifying-Unit Audit

      Before assigning score 2, identify at least one meaningfully developed
      player-facing how-problem or bounded problem-solving sequence in ordinary
      substantially-as-published play. State what the players must actually work out
      and why working out the solution is itself substantive play.

      Do not reach score 2 by adding together several situations that would each fail
      this test on their own. Checks, saves, searching, prescribed procedures, using a
      known key, item, or mechanism as instructed, ordinary route selection, obvious
      stated options, explicitly supplied social or other noncombat alternatives, and
      generic opportunities to improvise cleverly around an encounter do not
      independently establish score 2 when little remains for the players to work out
      about how to overcome the known problem.

      Those features can still participate in qualifying problem-solving when the
      authored situation leaves a substantive constraint, mechanism, resource tradeoff,
      or supported solution space for the players to reason through. The question is
      whether the player-facing how-problem remains substantive after prescribed
      resolution elements are removed, not how many clever-looking features are present.

      # Low-Anchor Counter-Pressure

      Do not overcorrect by requiring recurrence, multiple puzzles, formal riddles,
      difficult deduction, or a large share of total play for score 2. One localized
      but meaningfully developed puzzle, constrained planning challenge,
      resource-allocation problem, mechanism problem, or open-ended obstacle can be
      sufficient when solving how to overcome it constitutes meaningful player-facing
      play.

      In 1 ↔ 2 adjacent-anchor falsification, name the strongest candidate qualifying
      unit. To assign 2, explain what players must work out and why it survives the
      exclusion audit above. To assign 1, explain why the apparent candidates reduce
      to prescribed resolution, ordinary interaction or choice, another play mode, or
      generic player cleverness. Multiple non-qualifying candidates do not become a
      qualifying unit merely by accumulation.

      This guardrail clarifies application of the frozen AFAO rubric. It does not
      create benchmark-specific rules or alter the meaning of scores 1 or 2.
    TEXT

    SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Social Interaction Emphasis Boundary Application Guardrail v0.1

      When assessing Social Interaction Emphasis, apply the frozen AFAO anchors to the
      structural role of meaningful NPC interaction across ordinary substantially-as-
      published play. Do not compare Social Interaction against an aggregate total of
      every non-social mode, and do not require Social Interaction to be the sole or
      exclusive organizer of progression for score 5.

      # 2 ↔ 3 Boundary

      - Score 2 when meaningful NPC interaction occurs and matters but remains limited
        in extent or clearly secondary.
      - Score 3 when meaningful NPC interaction is a substantial recurring component
        alongside comparably important non-social play.
      - "Alongside comparably important non-social play" does not require Social
        Interaction to equal combat, exploration, puzzles, and other non-social modes
        added together. Test whether Social Interaction itself is substantial and
        recurring across ordinary play.
      - A recurring relationship or sequence of NPC-facing decisions can satisfy score
        3 even when woven through exploration or distributed across different scenes or
        NPCs rather than isolated in a formal social chapter or procedure.
      - Weight optional, bypassable, and path-dependent social material by expected
        presence. Do not automatically reduce it because any one scene can be skipped,
        and do not accumulate mutually exclusive branches as though all occur.

      # 4 ↔ 5 Boundary

      - Score 4 when Social Interaction is one dominant mode and regularly drives
        progress while major canonical progression also remains independently organized
        through non-social structures.
      - Score 5 when interacting with NPCs, relationships, or factions is a fundamental
        organizing structure of expected play, even when substantial exploration,
        combat, investigation, or problem solving also occurs.
      - "Fundamentally organized around" does not mean "organized only" or "organized
        exclusively." Ask whether social interactions repeatedly establish or enable
        major access, movement, objectives, information, alliances, permissions,
        bargains, or resolutions across the canonical adventure.
      - Do not require a single formal social mechanic or point track. Distributed
        social dependencies across multiple actors or relationships can collectively
        provide the primary structure.
      - Score 4 remains appropriate when major non-social structures carry substantial
        progression independently rather than largely occurring within or being enabled
        by Social Interaction.

      # Path and Adjacent-Anchor Falsification

      - An authored combat-forward, bypass, refusal, or low-social route does not by
        itself cap the score at 4 or reduce 3 to 2. Weight substantially-as-published
        expected play and represent materially different supported trajectories with
        Path Sensitive.
      - Before assigning 2 instead of 3, identify why the social play is not substantial
        and recurring without using "other modes combined are larger" as the reason.
      - Before assigning 4 instead of 5, identify the major independently progress-
        bearing non-social structure without relying on "significant non-social play
        exists" or "social is not the only organizer."

      This guardrail clarifies application of the frozen AFAO rubric. It does not alter
      the score anchors, create benchmark-specific rules, or presume that a higher
      Social Interaction Emphasis score is preferable.
    TEXT

    # v0.1 remains frozen above as the first Social Interaction Emphasis boundary
    # intervention. v0.2 adds only a 3 ↔ 4 dominance-preservation clarification
    # so the upper-boundary structural tests do not leak downward.
    SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_2 = (
      SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_1 + <<~TEXT

        # Social Interaction Emphasis 3 ↔ 4 Dominance Preservation v0.2

        Apply this clarification only to the 3 ↔ 4 boundary. It does not modify the
        v0.1 rules for 2 ↔ 3, 4 ↔ 5, or path-sensitivity weighting.

        Do not require Social Interaction to independently carry major canonical plot
        progression, gate the central objective, or provide necessary access or
        resolution in order to qualify for score 4. Those are not prerequisites for
        the High anchor.

        Score 4 when meaningful NPC interaction is one of the dominant modes across
        expected substantive table play and regularly drives progress through
        relationships, cooperation, persuasion, deception, rivalry, faction
        interaction, or other substantive social engagement. Repeated major
        interaction-centered events or phases can support score 4 even when the
        adventure's central mystery, objective, or climax also advances through
        independent non-social structures.

        Preserve score 3 when Social Interaction is substantial and recurring but
        principally frames, directs, or supplements a separately dominant body of
        exploration, combat, investigation, or other non-social play rather than
        itself constituting one of the adventure's dominant modes. Recurrence,
        consequence, or narrative importance alone does not establish score 4.

        Do not import the 4 ↔ 5 tests concerning fundamental organizing structure,
        major access or movement, or whether non-social progression is independently
        carried into the 3 ↔ 4 decision. Apply those tests only after score 4 has
        independently been satisfied under the dominance-and-regular-progress test.

        This clarification preserves both sides of the boundary: it does not create a
        general upward preference for Social Interaction Emphasis and does not make
        every recurring social strand a dominant mode.
      TEXT
    ).freeze

    FANTASTIC_WEIRDNESS_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Fantastic Weirdness Application Guardrail

      For the 4 ↔ 5 Fantastic Weirdness boundary, do not reject score 5 merely
      because the adventure retains a familiar abstract objective, genre skeleton,
      or sequence of player-facing verbs such as investigate, infiltrate, traverse,
      rescue, negotiate, fight, or escape.

      Apply the AFAO replacement test to the adventure's substantive playable
      identity and experienced operating reality, not merely to its abstract plot.
      Ask whether conventionalizing most of the weird material would preserve the
      authored site, causal rules, traversal logic, encounter identity, progression
      structure, and operating reality that players substantively experience.

      If conventionalization would replace those adventure-defining structures
      while leaving only a generic objective or activity skeleton, that supports
      score 5 rather than score 4.

      Path variation or optional material may change how much additional weirdness
      appears in a particular playthrough, but must not reduce the score merely
      because a less-weird supported path exists when the mandatory operating
      reality itself fundamentally constitutes the adventure's weird playable
      identity.

      This guardrail clarifies application of the frozen AFAO rubric; it does not
      create a separate score-5 criterion or presume that unusual material is
      automatically fundamentally weird.
    TEXT

    # v0.1 remains frozen above as the first Fantastic Weirdness 4 ↔ 5
    # intervention. v0.2 adds a counter-guardrail to prevent the replacement
    # test from collapsing "dominant weird experiential setting" into
    # "fundamentally weird operative playable structure."
    FANTASTIC_WEIRDNESS_GUARDRAIL_V0_2 = (
      FANTASTIC_WEIRDNESS_GUARDRAIL_V0_1 + <<~TEXT

        # Fantastic Weirdness 4 ↔ 5 Counter-Guardrail

        A bizarre, surreal, or convention-breaking site, setting, or fictional
        reality does not by itself establish score 5, even when it dominates
        player-facing experience.

        Score 4 remains appropriate when conventionalizing the weird material
        would substantially change the adventure's atmosphere, imagery,
        inhabitants, or experiential texture, but would leave its operative
        playable situation, progression structure, and principal forms of
        interaction recognizably intact.

        For score 5, the weirdness must materially constitute those operative
        structures themselves, not merely the distinctive fictional reality in
        which otherwise recognizable adventure play occurs.
      TEXT
    ).freeze

    SERIOUSNESS_ADVERSARIAL_PLAY_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Seriousness Adversarial-Play Guardrail

      When assessing Seriousness, distinguish playfulness in challenge design from
      playfulness in the adventure's expected dramatic register.

      Do not infer a lighter Seriousness register merely from trick traps, gotcha
      mechanics, deceptive puzzles, false rewards or endings, absurd punitive
      outcomes, adversarial dungeon design, or DM-facing amusement at player
      misfortune. Such material may be cruel, bizarre, humiliating, arbitrary, or
      game-like without making the expected player-facing table experience comic,
      playful, whimsical, or lighthearted.

      Count adversarial or funhouse-style material against sustained seriousness
      only when the published presentation supports it as a substantive lighter
      player-facing tonal register, rather than merely as the method, structure, or
      consequence of a challenge.

      In adjacent-anchor falsification, do not use designer or DM amusement, the
      absurdity of a punishment, or the trickiness of a challenge as a proxy for a
      lighter dramatic register. Evaluate whether substantially-as-published play
      actually sustains meaningful comic, playful, whimsical, or lighthearted
      counter-register material for the players.
    TEXT

    # v0.1 remains frozen above as the adversarial-play intervention that
    # corrected playfulness-of-challenge-design leakage. v0.2 adds tonal-
    # hierarchy proxy weighting for the Seriousness 2 ↔ 3 and 3 ↔ 4 boundaries.
    SERIOUSNESS_GUARDRAIL_V0_2 = (
      SERIOUSNESS_ADVERSARIAL_PLAY_GUARDRAIL_V0_1 + <<~TEXT

        # Seriousness Tonal-Hierarchy / Proxy-Weighting Guardrail

        Determine Seriousness from the relative substantive weight of the
        player-facing playful/lighthearted and earnest/dramatic registers across
        expected play. Do not substitute adjacent AdventureFinder dimensions,
        objective stakes, or surface genre vocabulary for that tonal comparison.

        For the 3 ↔ 4 boundary:
        - Danger, urgency, lethality, catastrophic stakes, betrayal, severe
          consequences, hostile opposition, a strict deadline, or a dramatically
          important objective do not by themselves establish that the
          earnest/dramatic register predominates.
        - Score 4 requires a clear tonal hierarchy in substantially-as-published
          play: the earnest/dramatic register must shape most of the expected
          experience while meaningful lighter material remains present.
        - When substantial caper, festival, flamboyant, comic, playful, or
          lighthearted presentation remains part of the central expected play,
          do not dismiss it as mere setup, color, or peripheral material solely
          because later objectives are dangerous, urgent, or consequential.

        For the 2 ↔ 3 boundary:
        - Whimsical, fairy-tale, fantastical, surreal, eccentric, colorful, or
          nonviolent presentation does not by itself establish that the
          playful/lighthearted register predominates.
        - Score 3 is appropriate when recurring earnest/dramatic material
          substantively shapes major phases, relationships, conflicts,
          conditions, objectives, or resolutions across expected play such that
          it is comparably substantial to the lighter register, even when both
          occur inside a consistently whimsical or fantastical fictional world.
        - Do not reduce substantive earnest/dramatic material to an
          "undercurrent" merely because it is expressed through whimsical
          imagery, eccentric characters, riddles, unusual bargains, fantastic
          creatures, or nonviolent problem solving.

        In adjacent-anchor falsification, explicitly identify the player-facing
        evidence that establishes tonal predominance or the absence of a clear
        tonal hierarchy. Stakes, danger, horror, Fantastic Weirdness, and
        game-like challenge may coexist with a register but must not stand in for
        evidence of that register.
      TEXT
    ).freeze

    DARKNESS_HORROR_INTENSITY_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Darkness / Horror Intensity Lower-Boundary Application Guardrail v0.1

      When assessing Darkness / Horror Intensity, weight qualifying dark material
      by its player-facing experiential role in ordinary substantially-as-published
      play. Do not convert the existence or narrative importance of a grim fact
      directly into darkness intensity.

      # Experiential Accounting

      - Danger, lethality, catastrophic stakes, villainy, betrayal, criminality,
        time pressure, possible death, or the existence of undead, fiends,
        grotesque creatures, sinister objects, or grim lore do not by themselves
        establish a higher Darkness / Horror score.
      - Background history, objective-level stakes, lore, and possible consequences
        count only to the extent they become substantive disturbing, frightening,
        horrific, grim, or emotionally dark player-facing experience.
      - Weight optional, random, mutually exclusive, bypassable, and path-dependent
        dark material according to its expected presence in ordinary substantially-
        as-published play. Do not aggregate every possible dark encounter or branch
        into one expected playthrough.

      # 1 ↔ 2 Boundary

      - Score 1 remains available when real stakes, sinister implications, betrayal,
        dangerous supernatural threats, or lethal consequences exist but qualifying
        darkness is exceptional, localized, backgrounded, or mainly functions as
        adventure danger inside a fundamentally non-dark experience.
      - Score 2 requires a meaningful player-facing dark experiential strand. Do
        not promote 1 to 2 merely because grim material is consequential, "more
        than decorative," or thematically important; identify how qualifying
        darkness itself materially enters expected substantive play.
      - Score 2 does not require darkness to recur across most phases. Limited,
        mild, intermittent, or clearly secondary darkness can still satisfy 2 when
        it is genuinely experienced rather than merely implied by stakes or lore.

      # 2 ↔ 3 Boundary

      - Score 2 when qualifying darkness remains limited, mild, intermittent,
        localized, or clearly secondary, even if dark facts, corpses, undead,
        grotesque creatures, or grim backstory recur.
      - Score 3 when qualifying darkness itself is a substantial recurring component
        of expected substantive play. Recurrence across multiple substantive phases,
        locations, relationships, objectives, or resolutions is supporting evidence
        when those appearances carry real disturbing, frightening, grim, horrific,
        or emotionally dark experiential weight.
      - Do not require score 3 darkness to become the dominant, primary, coequal,
        or majority experiential register. A fundamentally heroic, adventurous,
        whimsical, comic, or otherwise non-horror frame can still score 3 when
        qualifying darkness is a substantial recurring component.
      - Conversely, repeated dark props or facts do not establish 3 when their
        experiential role remains bounded or backgrounded and clearly secondary.
        Repetition is evidence only when the qualifying dark experience itself is
        substantial.

      # Lower-Boundary Adjacent-Anchor Falsification

      Before choosing among scores 1, 2, and 3, explicitly test:
      1. Does the cited evidence create substantive player-facing darkness, or mainly
         establish danger, stakes, lore, possible consequences, or genre dressing?
      2. If player-facing darkness exists, is it exceptional or localized enough for
         1, meaningful but bounded or intermittent enough for 2, or substantial and
         recurring enough for 3?
      3. For a proposed 3, would the reason for rejecting it incorrectly require
         darkness to dominate, become coequal, or define the whole adventure? If so,
         reject that proxy and reapply the score-3 anchor.

      Evaluate Path Sensitive independently of the integer score. Published paths
      can materially intensify, soften, or alter the form or amount of qualifying
      darkness without crossing an integer boundary.

      This guardrail clarifies application of the frozen AFAO rubric. It does not
      alter the score anchors, create benchmark-specific rules, or presume that a
      lower score is preferable.
    TEXT

    STRUCTURAL_OPENNESS_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Structural Openness Structural-Scale / Play-Coverage Guardrail v0.1

      When assessing Structural Openness, weight a choice or constraint by the amount
      of expected substantive adventure progression it governs. Do not weight it
      merely by how high it appears in a chapter, realm, deck, site, or campaign
      flowchart.

      Before choosing an anchor, reconstruct two layers separately:
      1. mandatory macro gates, transitions, convergence points, and campaign spine;
      2. the substantive bodies of play that occur within or between those points.

      Then ask across ordinary substantially-as-published play: who usually determines
      the next substantial route, objective, location, or scene—the publication or the
      players? Apply the AFAO anchors to the amount of substantive progression governed
      by each structure, not merely to the presence of branching or gates.

      # Structural Scale / Lower-Boundary Accounting

      - For the 1 ↔ 2 boundary, a choice must redirect a substantial authored route,
        objective, location, or sequence to clear score 1. An optional detour, room
        choice, side passage, encounter approach, or local routing choice that leaves
        the same prescribed objective and next major destination intact does not by
        itself increase Structural Openness.
      - For the 2 ↔ 3 boundary, distinguish one or a few localized or concentrated
        substantial choices from player-selected progression that recurs across
        substantial portions of expected play. Do not promote a bounded branch to 3
        merely because the branch itself is substantial.

      # Gate Non-Absolutism / Upper-Boundary Accounting

      - A required entry, chapter/realm/deck order, access gate, transition, milestone,
        late convergence, required climax, or eventual endpoint is evidence of
        prescription only to the extent that it determines substantive progression.
      - For the 3 ↔ 4 boundary, do not cap an otherwise High structure at 3 merely
        because a meaningful spine or fixed gates exist. Ask whether those constraints
        determine most of the substantive journey, or instead mainly frame or connect
        large bodies of player-directed progression.
      - Preserve score 3 when the fixed spine, mandatory sequence, or major gates
        repeatedly determine substantial next phases across much of expected play.
        Recurring openness alone does not establish 4 when the prescribed structure
        still governs most of the journey.
      - For the 4 ↔ 5 boundary, do not cap an otherwise Dominant structure at 4 merely
        because it has a common entrance, endpoint, clock, transition, or light access
        gate. Ask whether any single prescribed sequence governs most substantive
        expected play.
      - Preserve score 4 when player-directed progression is dominant across much of
        play but a meaningful macrosequence or campaign spine still shapes substantial
        portions of the journey. Score 5 requires player-directed selection and
        ordering to function as the fundamental organizing structure rather than merely
        dominating within a still-substantial prescribed macrosequence.
      - Conversely, a broad site, many available locations, or multiple exits do not
        establish high openness when the same prescribed objective and next major
        destination continue to govern substantive progression.

      # Expected-Play Coverage

      - Do not underweight authored wandering, quest selection, location selection, or
        route selection merely because it is optional or not required by the shortest
        completion path. Weight it by its expected presence in ordinary substantially-
        as-published play.
      - Do not accumulate every mutually exclusive or technically available branch as
        though all occur in one playthrough. The question is how ordinary expected play
        is structurally organized.
      - A mandatory transition can be structurally small even when narratively
        important; an open body of play can be structurally large even when many
        individual locations inside it are optional.

      In adjacent-anchor falsification, identify the specific choice or constraint used
      to distinguish the anchors and state the scope of substantive expected play it
      governs. Reject boundary reasoning that reduces to "a gate or spine exists,
      therefore the score is at most 3 or 4" or "some local route choice exists,
      therefore the score is at least 2." Apply the frozen AFAO anchors to structural
      coverage, not mere feature presence.

      This guardrail clarifies application of the frozen AFAO rubric. It does not alter
      the score anchors, create benchmark-specific rules, or presume that a higher or
      lower Structural Openness score is preferable.
    TEXT

    # v0.1 remains frozen above as the structural-scale / play-coverage
    # intervention. v0.2 adds narrow counter-guardrails for container-order
    # conflation, successful-path filtering, and temporal-frame overcounting.
    STRUCTURAL_OPENNESS_GUARDRAIL_V0_2 = (
      STRUCTURAL_OPENNESS_GUARDRAIL_V0_1 + <<~TEXT

        # Structural Openness Container-vs-Progression Counter-Guardrail v0.2

        This clarification refines how the v0.1 play-coverage test is applied. It
        does not create a general preference for higher Structural Openness scores.

        # Container Order Is Not Substantive Play Order — 3 ↔ 4

        When applying v0.1's instruction to preserve score 3 when fixed structure
        repeatedly determines substantial next phases, do not satisfy that test
        merely because the publication determines which broad chapter, realm, deck,
        region, or site is entered next.

        A macro gate's structural weight comes from how much substantive authored
        progression it prescribes after that transition. If a gate mainly selects the
        next broad container while players then choose among substantial routes,
        objectives, locations, or scenes within that container, treat the gate as a
        connector or frame for that player-directed body of play. Do not count the
        open body's substantive content as prescribed merely because its container was
        reached in a fixed order.

        Several large player-directed bodies can collectively make player choice
        dominant across much of expected play even when those bodies must be entered
        in a fixed order and each requires a mandatory transition or access condition.

        Preserve score 3 when fixed structure does more than select the next container:
        it must materially prescribe substantial objectives, scenes, routes, or
        sequences within those bodies, repeatedly narrow what substantive play can
        occur next, or itself occupy enough expected substantive play that openness
        remains Mixed rather than dominant. A fixed chapter or region order is not
        sufficient by itself, but neither is openness inside a region sufficient by
        itself to establish score 4.

        In 3 ↔ 4 adjacent-anchor falsification, identify separately:
        1. who determines the order of broad containers; and
        2. who determines the substantive progression within and between them.

        To hold at score 3 because of a spine or gate, identify the substantive play
        that the fixed structure actually prescribes beyond merely naming the next
        container or unlocking access to it.

        # Developed Alternate Routes Are Still Structural Choice

        Expected-play weighting is not successful-path filtering. Do not restrict
        Structural Openness analysis to the shortest, safest, optimal, or ultimately
        successful route through the adventure.

        A player-selected false, punitive, looping, dangerous, or ultimately
        nonprogressing route counts when choosing it launches a substantial authored
        sequence that ordinary exploration could genuinely enter. The route's failure,
        danger, deception, or later reconvergence does not erase the structural choice
        that produced that substantive body of play.

        Conversely, immediate dead ends, single-room trap branches, fake doors,
        trivial side passages, or choices that terminate without a substantive
        developed sequence do not gain structural weight merely because they are
        technically selectable. Continue to probability-weight mutually exclusive
        routes rather than summing all authored content into one imagined playthrough.

        # Temporal and Endpoint Framing Is Not Automatically Sequence — 4 ↔ 5

        A clock, timed event schedule, common entrance, common endpoint, or mandatory
        final transition is a prescribed progression sequence only to the extent that
        it actually determines which substantial authored scene, objective, location,
        or route occurs next.

        Timed events can interrupt or frame an otherwise freely ordered body of play
        without organizing most of that body's substantive progression. Temporal
        framing around player-directed play is not itself a progression sequence.

        Preserve score 4 when a meaningful macrosequence or campaign spine genuinely
        organizes substantial portions of expected play even though player-directed
        progression is dominant elsewhere. Score 5 still requires player-directed
        selection and ordering to be the fundamental organizing structure across the
        canonical unit; a common frame alone neither defeats nor establishes 5.

        In 4 ↔ 5 adjacent-anchor falsification, distinguish the ordering of timed or
        framing events from the ordering of substantive routes, objectives, locations,
        and scenes that players actually select. Do not use the existence of a clock
        or endpoint as a proxy for a prescribed substantive journey.

        This counter-guardrail clarifies application of the frozen AFAO anchors and
        v0.1 coverage test. It does not create benchmark-specific rules or presume
        that a higher Structural Openness score is preferable.
      TEXT
    ).freeze

    CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Consequential Player Agency 1 ↔ 2 Application Guardrail

      When distinguishing Consequential Player Agency score 1 from score 2,
      distinguish an authored player-caused adventure-state consequence from the
      successful or unsuccessful resolution of a challenge.

      A player action does not establish score 2 merely because it causes something
      to remain different afterward. "Persistent state" in this dimension does not
      mean merely that a physical condition, resource, creature, hazard, route, or
      other factual state continues to exist. The difference must constitute a
      substantive authored adventure state, relationship, event, objective, or
      downstream condition produced by player decision.

      Score 1 remains appropriate when choices principally determine:
      - whether or how a puzzle, trap, encounter, or environmental obstacle is solved;
      - success or failure within a challenge;
      - immediate access, route, timing, survival, or encounter conditions;
      - acquisition, loss, or expenditure of resources or mechanical advantages;
      - localized environmental changes that principally affect resolution of the
        current obstacle or subsequent traversal;
      even when those effects are durable or consequential to survival.

      In particular, do not convert puzzle correctness, successful checks, trap
      handling, environmental manipulation, or other problem-resolution outcomes
      into score-2 agency merely because success and failure have different
      consequences.

      A follower, ally, item, shortcut, environmental advantage, or similar benefit
      received as the payoff for successfully resolving a challenge does not by
      itself establish score 2 merely because it can persist beyond that encounter.
      Determine whether the publication authors a substantive continuing
      relationship or adventure-state consequence beyond the benefit's role as a
      challenge reward.

      Score 2 begins when at least one meaningful player decision creates a
      substantive authored difference that is not merely the success/failure,
      method, resource, access, or survival result of resolving the current
      challenge. Qualifying consequences may remain localized or optional and may
      later reconverge.

      Examples of qualifying forms include:
      - a player decision establishing or changing a continuing NPC or faction
        relationship;
      - accepting, rejecting, or altering an objective in a way that changes the
        party's subsequent authored task or state;
      - a player decision causing a later authored event or condition to differ;
      - another player-caused state that the publication substantively carries
        forward beyond resolution of the immediate challenge.

      For adjacent-anchor falsification, before assigning score 2 identify at least
      one qualifying causal chain:

          meaningful player decision
          -> substantive authored adventure-state difference
          -> that difference persists into or materially changes subsequent play

      If the cited evidence instead terminates in puzzle resolution, encounter
      success or failure, access, traversal, survival, timing, resources, or a
      mechanical reward without a substantively authored downstream state, it does
      not by itself defeat score 1.

      Do not require recurring consequences, broad branching, or a changed ending
      for score 2. One genuinely qualifying localized consequence is sufficient.
    TEXT

    # v0.1 remains frozen above as the initial Consequential Player Agency
    # 1 ↔ 2 challenge-resolution intervention. v0.2 adds a narrow 2 ↔ 3
    # clarification for the score-3 single-major-outcome route.
    CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_2 = (
      CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_1 + <<~TEXT

        # Consequential Player Agency 2 ↔ 3 Major-Outcome Clarification

        A consequence that qualifies for score 2 does not become score 3 merely
        because the person, object, objective, relationship, or fictional subject it
        affects is important, plot-critical, prophecy-linked, powerful, or valuable.

        When applying score 3's rule that a meaningful decision may determine a major
        outcome, assess the magnitude of the authored adventure outcome caused by the
        decision, not merely the narrative importance of what the decision concerns.

        A bounded secondary objective, artifact disposition, relationship state, or
        other localized consequence may remain score 2 even when its subject is highly
        important, if the canonical adventure's major progression, resolution, and
        downstream situation substantially reconverge.

        Likewise, do not treat a nominal alternative as a qualifying major outcome when
        the publication merely gestures toward that alternative but leaves its
        substantive continuation or resolution to GM invention. The score-3
        major-outcome clause requires a substantively authored alternate outcome, not
        an inferred one.
      TEXT
    ).freeze

    # v0.2 remains frozen above as the lower-bound CPA prompt profile. v0.3 adds
    # an upper-boundary clarification for the 3 ↔ 4 and 4 ↔ 5 distinctions.
    CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_3 = (
      CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_2 + <<~TEXT

        # Consequential Player Agency 3 ↔ 5 Structural Consequence Clarification

        The 2 ↔ 3 major-outcome clarification above governs whether a bounded
        consequence independently qualifies through score 3's single-major-outcome
        route. Do not generalize macro reconvergence into a ceiling on higher
        Consequential Player Agency scores.

        For the 3 ↔ 4 boundary, assess the recurrence, magnitude, and downstream
        reach of player-caused consequences across the canonical adventure.

        Fixed major developments, a shared macro progression, or a substantially
        common endpoint do not cap an adventure at score 3 when player decisions
        nevertheless create recurring major differences in later authored play
        across much of the canonical unit.

        Score 4 can arise through either:
        - multiple consequential threads recurring across widely separated phases
          of the adventure; or
        - one deeply integrated, repeatedly reactive relationship or state system
          whose player-caused state changes materially alter subsequent authored
          play across much of the adventure.

        Do not discount an integrated consequential system merely because its
        effects manifest as assistance, hostility, access, objectives, conditions,
        resources, advantages, or encounter circumstances. Assess how broadly and
        repeatedly the continuing player-caused state changes downstream play, not
        the surface category of each individual effect.

        Conversely, numerous localized consequences, route selections, rewards, or
        one-time state changes do not establish score 4 unless their consequential
        reach satisfies the High anchor.

        For the 4 ↔ 5 boundary, distinguish recurring major consequential agency
        from cumulative decision history functioning as an organizing feature of
        later play.

        Score 5 does not require multiple wholly different plotlines, a different
        geographic progression, a different central crisis, or multiple radically
        different endings. A substantially shared macro progression or endpoint
        does not prevent score 5.

        Evidence for score 5 includes a publication repeatedly preserving and
        consulting accumulated player-caused history across multiple independent
        channels—for example relationships, statuses, bargains, objectives, events,
        advantages or disadvantages, persistent conditions, later reactions, and
        resolution conditions—such that later authored play materially depends on
        the history of earlier player decisions.

        An explicit tracker is strong evidence of this structure but is not
        required. Likewise, individual tracked consequences need not each be major
        in isolation when their cumulative cross-adventure operation makes player
        decision history a fundamental organizing feature.

        Score 4 remains appropriate when consequential choices are recurring and
        major but operate as discrete threads or through one integrated reactive
        system without accumulated decision history becoming a cross-adventure
        organizer across multiple independent state channels.
      TEXT
    ).freeze

    GM_IMPROVISATION_DEMAND_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # GM Improvisation Demand 3 ↔ 5 Runtime-Synthesis Guardrail

      When assessing GM Improvisation Demand, do not treat the amount, detail,
      completeness, or usefulness of published material as a direct negative proxy
      for improvisation demand.

      Published locations, encounters, NPC motivations, factions, goals, tables,
      procedures, events, and other authored foundations reduce improvisation demand
      only to the extent that they actually specify the playable response,
      consequence, transition, or situation the GM needs at the table.

      An adventure may contain extensive and highly detailed published material while
      still requiring High or Very High GM Improvisation Demand if ordinary play
      regularly requires the GM to synthesize those foundations into situation-specific
      responses to player action.

      For the 3 ↔ 4 boundary:

      - Score 3 remains appropriate when improvisational episodes recur but substantial
        published playable material still carries most ordinary play, so the GM can
        usually return quickly to sufficiently specified responses or sequences.

      - Score 4 begins when successful ordinary play regularly depends on the GM
        transforming authored foundations into substantive playable responses,
        consequences, transitions, or evolving situations that the publication does
        not itself sufficiently specify.

      - Do not hold an adventure at score 3 merely because major locations, encounters,
        NPCs, objectives, or later set pieces are extensively authored. Ask whether the
        connective and reactive play between or within those foundations is itself
        sufficiently specified.

      For the 4 ↔ 5 boundary:

      - Score 4 may contain extended high-improvisation phases while sufficiently
        specified material still carries substantial portions of expected play.

      - Score 5 does not require the GM to invent the adventure, its principal
        locations, major NPCs, central conflict, or authored content from scratch.

      - Score 5 begins when large portions of ordinary substantive play are carried by
        wide-latitude runtime synthesis: the GM must routinely integrate published
        foundations, accumulated player actions, evolving relationships or states, and
        current circumstances into consequential playable situations whose specific
        responses or outcomes are not sufficiently authored in advance.

      For adjacent-anchor falsification, ask:

      1. What substantive playable response or consequence is required at the table?
      2. Does the publication actually specify that response or consequence, or mainly
         supply foundations from which the GM must construct it?
      3. How often does that synthesis occur across ordinary substantially-as-published
         play?
      4. At the upper boundary, does runtime synthesis merely recur in substantial
         phases, or does it itself carry large portions of ordinary play?

      Do not award score 4 or 5 merely because an adventure is open-ended, nonlinear,
      sandbox-like, socially complex, or rich in NPCs. Those features matter only when
      they produce the runtime synthesis described above.

      This guardrail clarifies application of the frozen AFAO rubric. It does not alter
      the score anchors or create an additional criterion.
    TEXT

    LEVELS_NESTED_CONTEXT_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Levels Nested-Adventure Context / Inherited Entry-State Guardrail v0.1

      Canonical boundaries define the playable adventure being assessed, but they do
      not erase explicit published entry-state guidance that governs characters as
      they enter a nested canonical unit.

      If the canonical page slice does not restate Level Start, use supplied
      pre-canonical Levels context to look for direct editorial guidance establishing
      the characters' level immediately before or at entry. Such guidance may establish
      Level Start without importing the parent campaign's full level span.

      Prefer explicit starting-level or advancement statements. If no direct statement
      exists, infer a discrete Level Start only when published progression unambiguously
      establishes the characters' level immediately before entry. Mere chapter order,
      anthology position, encounter difficulty, expected progression, or the parent
      campaign's overall level range is insufficient.

      Assess Level End separately. Count only advancement owned by the canonical unit.
      Advancement triggered only after leaving it or entering a subsequent canonical
      unit does not count backward. If Level Start is established and the published
      evidence establishes that no advancement occurs before completion of the
      canonical unit, Level End may equal Level Start.

      Supplemental pre-canonical context is evidence only for Levels entry state and
      directly governing progression. Do not use it to broaden canonical playable
      scope or infer other AdventureFinder dimensions.

      Preserve uncertainty when the publication provides only qualitative guidance
      such as "high-level characters" or otherwise fails to establish a discrete level.
      Do not guess from difficulty or placement alone.
    TEXT

    LETHALITY_FAILURE_SEVERITY_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Lethality / Failure Severity Failure-Conversion Guardrail v0.1

      When assessing Lethality / Failure Severity, translate danger into the score
      through the published consequence profile of failure, not exposure to danger
      alone. The governing question is what ordinary mistakes, losses, and failed
      decisions are actually authored to become in substantially-as-published play.

      # Authored Failure-Conversion Audit

      For the strongest candidate severe situations, trace:
      1. the mistake, failed decision, failed check, lost encounter, or other failure;
      2. the published state that follows that failure; and
      3. whether that state is severe and lasting or irreversible, or is meaningfully
         buffered by a supported route back into continued play.

      Do not infer recurring severe consequences merely from recurring encounters in
      which PCs could theoretically die. Character death is a qualifying severe
      consequence when the published situation makes death a readily credible result;
      the ordinary theoretical possibility that combat can kill characters is not
      sufficient by itself.

      Explicitly credit authored warning, mitigation, retreat, capture,
      unconsciousness, rescue, resurrection, recovery, alternate progression,
      fail-forward procedures, and other supported continuation states. These
      features do not erase danger; they change how readily failure converts into a
      severe, lasting, or irreversible consequence.

      Temporary hit-point damage, expendable resource loss, temporary conditions,
      minor delays, and readily reversible setbacks remain non-severe unless the
      published sequence converts them into a qualifying lasting consequence.

      # Recurrence and Expected-Play Weighting

      Count recurrence of qualifying severe failure conversions, not recurrence of
      combat, hazards, difficult encounters, or opportunities to make mistakes. A
      long adventure with many dangerous scenes is not automatically more lethal if
      the publication repeatedly converts defeat into recoverable states.

      Rare, highly optional, path-dependent, or overextension-dependent catastrophic
      branches receive less weight than severe outcomes embedded in ordinary expected
      play. Do not let one optional total-party-loss or irreversible branch establish
      the whole-adventure score when ordinary published play supplies substantial
      buffers and continuation.

      # Adjacent-Boundary Application

      For 1 ↔ 2:
      - Preserve 1 when ordinary failures overwhelmingly convert into temporary or
        recoverable states and severe outcomes remain exceptional or strongly
        buffered, even if an isolated dangerous situation could theoretically become
        severe.
      - Use 2 when severe consequences become genuinely possible in ordinary supported
        play but remain uncommon, substantially avoidable, or localized.

      For 2 ↔ 3:
      - Score 3 only when severe failure itself becomes a meaningful recurring
        possibility across substantive play; recurring dangerous encounters alone do
        not satisfy this boundary.
      - Substantial warning, mitigation, retreat, recovery, alternate progression, or
        fail-forward support can coexist with score 3.

      For 3 ↔ 4:
      - Preserve 3 when published safety valves remain substantial enough that severe
        outcomes recur as credible possibilities but failure often has meaningful
        margins for avoidance, retreat, recovery, or continuation.
      - Score 4 when severe consequences are both recurring and readily credible and
        those protections become materially limited. Do not demote a genuine 4 merely
        because some warning, allies, or escape options exist; assess whether those
        protections remain reliable against the central expected failure states.

      For 4 ↔ 5:
      - Preserve 4 when the adventure is highly dangerous but still supplies meaningful
        ramp-up, warning, information, mitigation, or supported recovery.
      - Score 5 only when severe or catastrophic failure is pervasive or structurally
        central and relatively discrete mistakes can readily produce irreversible or
        adventure-ending outcomes with little reliable margin for recovery.

      In adjacent-anchor falsification, cite the actual authored
      failure -> resulting state -> recovery/irreversibility chain used to place the
      score. Do not use combat frequency, encounter difficulty, danger density, or raw
      incident count as a substitute for that chain.

      This guardrail clarifies application of the frozen AFAO rubric. It does not
      alter the anchors, create benchmark-specific rules, or presume that a higher or
      lower Lethality / Failure Severity score is preferable.
    TEXT

    RULES_SYSTEM_MASTERY_DEMAND_UPPER_SCALE_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Rules / System-Mastery Demand — Upper-Scale Adjudication Guardrail

      When distinguishing scores **3, 4, and 5**, judge the **continuity and progression importance of player-facing mechanical understanding**, not whether the adventure presents one unified bespoke subsystem.

      **Do not require a score of 4 to involve a single persistent or player-controlled system.** A continuing mechanical environment or ecology can qualify when rules, information, state, interactions, or mechanical tools remain relevant across multiple challenges or locations and materially shape access, traversal, available options, resources, or resolution. Individual mechanisms may appear locally while still forming a continuing mechanical demand across the adventure.

      **Do not require a score of 5 to use one persistent subsystem, one type of mechanic, or adventure-wide universal coverage.** Extreme demand can arise through any of several forms, including:

      - repeatedly operating a persistent mechanical system;
      - repeatedly exploiting or responding to consequential exact-rule interactions within a recurring mechanical environment; or
      - repeatedly adapting to materially different mechanical states, constraints, or responses across major challenges.

      A system being **explicitly taught, stable once learned, discoverable, or straightforward to execute after it is understood does not by itself reduce its System-Mastery Demand**. If progression repeatedly depends on retaining and correctly applying that mechanical understanding, the fact that the procedure becomes familiar is not a reason to cap the score at 4.

      Likewise, do not cap an adventure below 5 merely because its demanding mechanics are **different from one another rather than components of one unified system**. If multiple major challenges repeatedly make understanding and adapting to their mechanical operation a principal part of effective progression or resolution, that differentiated mechanical demand can satisfy the Extreme band.

      As a boundary check:

      - **3 → 4:** Ask whether demanding mechanics remain largely localized/discrete, or whether mechanical understanding has continuing importance across multiple substantive challenges or locations.
      - **4 → 5:** Ask whether the continuing mechanical environment mainly shapes how play proceeds, or whether **operating, exploiting, or adapting to mechanics repeatedly becomes itself a principal progression challenge**.
    TEXT

    # v0.1 remains frozen above as the upper-scale morphology clarification. v0.2
    # adds a narrow score-5 clarification for stable learned system operation.
    RULES_SYSTEM_MASTERY_DEMAND_UPPER_SCALE_GUARDRAIL_V0_2 = (
      RULES_SYSTEM_MASTERY_DEMAND_UPPER_SCALE_GUARDRAIL_V0_1 + <<~TEXT

        # Score-5 Stable Learned Operation Clarification v0.2

        When a candidate score-5 system is repeatedly required for progression, do not
        ask whether each individual operation remains difficult after the rules are
        learned. Ask whether players must repeatedly retain, apply, and operationalize
        that mechanical understanding to progress through major challenges.

        Repetition of a stable learned procedure can itself constitute repeated system
        operation. "The procedure is straightforward once understood," "the rules are
        stable," or "the system is explicitly taught" are not evidence that system
        operation is not a principal progression challenge when successful progression
        repeatedly depends on applying that understanding.

        Distinguish execution difficulty from progression role. A procedure need not
        become newly puzzling, tactically difficult, or mechanically novel each time it
        is used to qualify as repeated operation. Conversely, merely repeating a simple
        rule is not sufficient for score 5 unless operating it repeatedly functions as
        a principal progression challenge under the AFAO Extreme anchor.
      TEXT
    ).freeze

    # v0.2 remains frozen above as the stable-operation clarification. v0.3 adds
    # a narrow 4 ↔ 5 decision procedure for persistent-system progression accounting.
    RULES_SYSTEM_MASTERY_DEMAND_UPPER_SCALE_GUARDRAIL_V0_3 = (
      RULES_SYSTEM_MASTERY_DEMAND_UPPER_SCALE_GUARDRAIL_V0_2 + <<~TEXT

        # Score-5 Persistent-System Progression Accounting / Morphology Isolation v0.3

        Apply this clarification only to the **4 ↔ 5 boundary**. Evaluate the recognized
        Extreme-demand forms independently. When a candidate qualifies through
        **repeated operation of a persistent mechanical system**, do not additionally
        require that its operations repeatedly introduce novel mechanics, materially
        different mechanical states, difficult execution, or adaptation to changing
        rules. Those are alternative ways Extreme demand can arise, not cumulative
        requirements of the persistent-system route.

        When a persistent player-facing system governs access, traversal, mechanical
        state, tools, resources, or required progression conditions, assess the **whole
        system-mediated progression loop**. Acquiring a required system state or tool,
        retaining or transferring it, selecting the appropriate state, applying it at
        the required place, and performing the system's required operation can all be
        parts of operating that system.

        Do not automatically reclassify those activities as merely "exploration,"
        "finding keys," "locating objectives," or another nonmechanical progression
        structure when their progression significance depends on the persistent
        system's mechanical rules. Likewise, combat or exploration occurring while
        players obtain required system state does not by itself make that state
        acquisition independent of the system.

        In this guardrail, **"principal progression challenge" is a structural test,
        not a difficulty test**. It does not mean that operating the system must be the
        hardest activity, consume most table time, dominate most locations, remain
        cognitively difficult after learning, or exclude substantial combat,
        exploration, or other play.

        Instead ask: **Across multiple major progression steps, does advancement
        repeatedly require players to retain, acquire, select, transfer, apply, or
        otherwise correctly operate the persistent mechanical system?** If so,
        repeated operation can itself satisfy the Extreme operating-structure
        requirement even when each individual operation is standardized or
        straightforward once understood.

        Preserve score 4 when the continuing system mainly modifies access,
        convenience, traversal, options, or resources while major progression
        ordinarily proceeds without repeatedly requiring correct operation of that
        system.

        Do not inflate to score 5 merely because an adventure contains keys, gates,
        repeated checks, or a recurring procedure. The system must be persistent and
        player-facing, and correct operation must repeatedly constitute a substantive
        requirement of major progression.
      TEXT
    ).freeze

    # v0.3 remains frozen above as the upper-scale production control. v0.4 adds
    # only a 1 ↔ 2 player-knowledge dependency clarification.
    RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_4 = (
      RULES_SYSTEM_MASTERY_DEMAND_UPPER_SCALE_GUARDRAIL_V0_3 + <<~TEXT

        # Rules / System-Mastery Demand 1 ↔ 2 Player-Knowledge Dependency Clarification v0.4

        Apply this clarification only to the **1 ↔ 2 boundary**. It does not modify
        the existing v0.1–v0.3 rules for scores 3–5.

        **Mechanical exposure is not itself System-Mastery Demand.** Score the extent
        to which successful player decisions depend on understanding and applying
        mechanics, not the number or variety of mechanical procedures the adventure
        invokes.

        For this boundary, **ordinary basic rules use is broader than attacks and
        ability checks alone**. Routine participation may include the GM calling for
        saving throws, applying common conditions, adjudicating stealth or surprise,
        using cover or difficult terrain, resolving climbing or falling, tracking
        light or visibility, applying movement restrictions, administering ordinary
        traps or environmental hazards, and resolving straightforward creature or item
        effects. The presence or recurrence of such procedures does not by itself
        establish score 2.

        Do not accumulate many individually routine procedures into Low demand merely
        because they occur in different encounters or locations. Breadth of ordinary
        rules exposure is not equivalent to player system mastery.

        Before assigning score 2, identify a **bounded but meaningful player-facing
        mechanical-knowledge dependency**: a situation in which understanding which
        rule, ability, resource, condition, interaction, or player-facing system
        applies materially informs what players should do for successful progression
        or effective resolution.

        Ask the counterfactual: **Could players generally participate effectively
        through straightforward or intuitive choices while the GM administers the
        relevant mechanics, or must players themselves understand and apply a
        particular mechanical relationship to make an effective choice?**

        A check, saving throw, condition, terrain rule, monster effect, trap procedure,
        or other mechanic does not qualify merely because its mechanical consequences
        matter. If the GM can administer the procedure and players can respond
        effectively through ordinary intuitive play without understanding the
        underlying interaction, it may remain compatible with score 1.

        Likewise, a prescribed adventure-specific effect does not automatically
        establish score 2 merely because it is unusual. Determine whether players must
        meaningfully learn, select around, exploit, manage, or apply its mechanics,
        rather than merely experience a rule the adventure or GM resolves for them.

        **Preserve score 2 when a localized mechanical interaction genuinely makes
        player understanding consequential.** Low does not require recurrence, a
        persistent subsystem, sustained mastery, or a mechanic that carries across the
        adventure. A bounded challenge can qualify when recognizing and correctly
        applying a particular rule, ability, resource, condition, interaction, or
        player-facing procedure materially improves or enables resolution.

        In 1 ↔ 2 adjacent-anchor falsification:
        - To assign **1**, explain why the strongest cited mechanics are principally
          routine, automatically adjudicated, prescribed, or otherwise usable through
          straightforward participation without meaningful player mechanical
          understanding.
        - To assign **2**, name the specific player-facing mechanical relationship
          players must meaningfully understand or apply and explain how that
          understanding affects their decision or resolution.

        Do not choose 2 merely because there are many mechanics, because the adventure
        uses rules beyond attacks and checks, or because mechanical consequences can
        affect success.
      TEXT
    ).freeze

    # v0.4 remains frozen above as the lower-boundary player-knowledge dependency
    # control. v0.5 adds only a narrow distinction between optional mechanical
    # advantage, intuitive fictional reasoning, and meaningful mechanical knowledge.
    RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_5 = (
      RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_4 + <<~TEXT

        # Rules / System-Mastery Demand 1 ↔ 2 Advantage-vs-Dependency Clarification v0.5

        Apply this clarification only to the **1 ↔ 2 boundary**. It refines v0.4's
        player-knowledge dependency test and does not modify the v0.1–v0.3 rules for
        scores 3–5.

        **A mechanically informed advantage is not automatically a mechanical-knowledge
        dependency.** Do not assign score 2 merely because knowing a rule, ability,
        interaction, or procedure can produce a bonus, shortcut, safer route, optional
        resource, alternate tactic, or improved local outcome.

        For score 2, lack of the cited mechanical understanding must create a meaningful
        player-facing disadvantage in effective participation or resolution, rather than
        merely causing the party to miss one advantageous option while straightforward
        or intuitive play remains sufficient. Score 2 does not require the mechanic to
        be mandatory or the only successful solution; it requires the mechanical
        understanding itself to materially shape effective player choice rather than
        merely optimize it.

        **Do not convert intuitive fictional reasoning into system mastery merely because
        the GM resolves that choice mechanically.** If players can identify an effective
        action from the fictional situation itself—such as an obvious risk, creature
        behavior, environmental fact, or explicitly described feature—without needing
        to understand the underlying mechanical relationship, the GM's subsequent check,
        modifier, condition, or mechanical consequence does not by itself establish
        score 2.

        Likewise, discovering that an authored feature grants a stated benefit and then
        choosing to use that benefit does not automatically establish Low demand. Ask
        whether players must understand or apply a mechanical relationship beyond simply
        recognizing and using the feature as presented.

        **Preserve score 2 when the mechanical relationship itself—not merely the
        fictional premise or the availability of an advantageous option—meaningfully
        determines what players must select, manage, apply, or do for effective
        resolution.** A localized interaction can still qualify even when another route
        exists, provided lack of the relevant mechanical understanding creates a
        substantive player-facing disadvantage rather than merely forfeiting an optional
        optimization.

        In 1 ↔ 2 adjacent-anchor falsification, when the strongest score-2 evidence is a
        beneficial option, ask whether the benefit demonstrates a real mechanical-
        knowledge dependency or only rewards an intuitive or optional choice. Do not let
        "mechanically useful" substitute for "successful play meaningfully depends on
        mechanical understanding."
      TEXT
    ).freeze

    # v0.5 remains frozen above as the lower-boundary advantage-vs-dependency
    # clarification. v0.6 adds a scale-band precedence rule so 1 ↔ 2 logic cannot
    # override independently established Moderate-or-higher evidence.
    RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_6 = (
      RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_5 + <<~TEXT

        # RSMD Scale-Band Precedence / 1↔2 and 2↔3 Firewall v0.6

        Apply this as a decision-order rule so lower-boundary clarifications do not
        override evidence for Moderate or higher. It does not replace the AFAO anchors
        and does not modify the existing 3 ↔ 4 or 4 ↔ 5 adjudication rules.

        First identify whether cited instances actually qualify as meaningful
        player-facing mechanical-knowledge demand under the v0.4/v0.5 distinctions.
        Routine mechanical exposure, GM-administered procedures, intuitive fictional
        choices, and merely optional mechanical advantages do not become qualifying
        demand merely because they recur.

        Then ask whether that qualifying demand recurs across multiple substantive
        challenges or locations in expected substantially-as-published play. If yes,
        the adventure has crossed the **2 → 3 threshold**. Do not reuse the v0.4/v0.5
        lower-boundary discounts as an adventure-global completion test to demote the
        candidate to 1 or 2. Continue adjudication only among scores 3–5.

        For the **2 ↔ 3 boundary, persistence is not required**. Score 2 when meaningful
        mechanical-knowledge demand is limited, secondary, or concentrated in one or a
        few bounded challenges. Score 3 when such demand is a recurring meaningful part
        of multiple substantive challenges or locations, even when the mechanics differ
        from place to place and no mechanical state, tool, or procedure carries forward.
        Continuing cross-location state, tools, procedures, or system continuity belongs
        to the 3 ↔ 4 boundary, not the 2 ↔ 3 boundary.

        Only when score 3 has not been established should the 1 ↔ 2 clarifications
        determine the final band.

        For the **1 ↔ 2 boundary**, a genuine mechanical-knowledge dependency may be
        bounded to one substantive challenge or resolution. Do not require the cited
        mechanic to recur, govern every route, or be necessary for overall adventure
        completion. Score 2 can be supported when effective resolution of that
        substantive challenge materially depends on players themselves recognizing and
        applying the relevant mechanical relationship.

        Preserve score 1 when the cited knowledge merely supplies an optional bonus,
        shortcut, safer tactic, extra resource, alternative approach, or improved local
        outcome while the same substantive challenge remains effectively resolvable
        through straightforward fictional reasoning and ordinary play.

        **Explicit teaching, clear publication, or easy discovery does not by itself
        erase a score-2 dependency.** Distinguish being told how a mechanic works from
        the GM simply administering the mechanic without mechanically informed player
        choice. A clearly presented rule can still support score 2 when players must
        select or apply that mechanical relationship to resolve a substantive challenge
        effectively.

        As a precedence check, if a rationale is about to assign 1 or 2 after already
        establishing recurring qualifying mechanical-knowledge demand across multiple
        substantive challenges or locations, stop and adjudicate 3–5 instead.
      TEXT
    ).freeze

    # v0.6 remains frozen above as the lower-band scale-precedence control. v0.9
    # adds an anchor-local sufficiency rule for the downward-bias pattern observed
    # when a boundary was rejected for lacking properties that belong to a higher band.
    RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_9 = (
      RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_6 + <<~TEXT

        # RSMD Anchor-Local Sufficiency / Next-Band Leakage Firewall v0.9

        Apply this as an **anchor-local decision rule** across the full 1–5 ladder.
        It does not instruct you to score upward, weaken evidence qualification, or
        ignore adjacent-anchor falsification. Instead, when deciding whether an
        adventure qualifies for a score, test that score against **its own positive
        AFAO conditions**. Do not require evidence that belongs to the next higher band
        as a prerequisite for awarding the current band.

        Once the positive conditions for score N are established, failure to establish
        score N+1 is a reason to stop at N, not a reason to fall back below N. In
        adjacent-anchor falsification, reject the higher candidate only for failure to
        satisfy that candidate's own requirements; do not manufacture an extra proof
        burden from a still-higher anchor.

        ## 1 ↔ 2 — prescribed does not mean GM-administered

        Preserve the v0.4–v0.6 anti-inflation rules. Routine mechanics, intuitive
        fictional choices, optional optimization, and procedures the GM can administer
        without mechanically informed player choice remain compatible with score 1.

        However, **explicitly taught, prescribed, scripted, or clearly discoverable is
        not synonymous with GM-administered**. A bounded challenge can support score 2
        when players themselves must recognize, select, remember, or apply the relevant
        beyond-basic mechanical relationship for effective resolution, even when the
        publication explains that relationship clearly. Do not require recurrence,
        persistence, sustained mastery, broad adventure coverage, or overall-completion
        necessity; those belong to higher-band questions.

        ## 2 ↔ 3 — recurrence is sufficient without score-4 continuity

        Once qualifying beyond-basic player-facing mechanical demand recurs as a
        meaningful feature across multiple substantive challenges or locations, score 3
        is established unless stronger upper-band evidence supports 4 or 5. **Localized,
        discrete, heterogeneous, or separately resolved mechanical problems are
        compatible with score 3.**

        Do not require a continuing player-operated system, persistent state,
        carry-forward tool, sustained operating layer, or progression-shaping mechanical
        ecology to award score 3. Those are possible score-4 evidence, not prerequisites
        for Moderate.

        ## 3 ↔ 4 — do not require score-5 progression structure to establish High

        Score 4 can be established through either:
        1. a continuing player-facing mechanical environment or system whose information,
           state, rules, interactions, or tools remain consequential across substantive
           play; **or**
        2. a sustained pattern of materially differentiated mechanical states or
           interactions that repeatedly requires continued interpretation and adaptation
           across substantive play.

        For score 4, that mechanical layer or adaptation pattern must materially shape
        access, traversal, options, resources, or resolution. **Do not require score-5
        progression-bearing operation to establish score 4.** In particular, do not
        reject 4 merely because operating or adapting to the mechanics does not itself
        repeatedly become a principal progression challenge.

        Preserve score 3 when the evidence remains a collection of recurring but chiefly
        localized or separately resolved problems and does not aggregate into either a
        sustained carry-forward mechanical layer or a sustained differentiated-response
        pattern. Mechanical variety or density alone does not establish score 4.

        ## 4 ↔ 5 — use the actual Extreme test; do not invent a phantom higher band

        Score 5 is established when, across multiple major challenges, successful
        progression or effective resolution repeatedly consists of correctly operating,
        interpreting, exploiting, or adapting to consequential mechanics. The qualifying
        major challenges must make mechanical mastery a defining operating structure of
        substantive play, not merely provide a continuing mechanical environment.

        Do **not** add requirements that the AFAO score-5 anchor does not contain. Do not
        require every qualifying challenge to be mandatory on every route, mechanical
        operation to dominate a majority of all play, every bypass to be impossible, or
        every mechanical error to prevent continued play. Those stricter conditions are
        not a hidden score-6 gate.

        At the same time, do not inflate to 5 from mechanical density, variety, a large
        collection of optional or completionist interactions, or a continuing mechanical
        layer that materially shapes play without repeatedly becoming the structure of
        major progression or effective resolution. Those remain compatible with 3 or 4.

        ## Final leakage check

        Before locking the score, inspect the reason used to reject each higher adjacent
        anchor. If the rationale says, in substance, "this is not N because it lacks a
        property first required by N+1," correct the boundary test and reassess. Apply
        the positive sufficiency and anti-inflation rules symmetrically; this firewall
        forbids next-band leakage, not conservative judgment.
      TEXT
    ).freeze

    PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # Player Beginner Suitability Support-vs-Difficulty Guardrail v0.1

      When assessing Player Beginner Suitability, measure how well the published
      playable structure supports an inexperienced player in learning to handle the
      adventure's demands. Do not measure how few demands, dangers, unfamiliar
      situations, or difficult decisions the adventure presents.

      Raw challenge is not a downward-scoring proxy. Character level, Rules /
      System-Mastery Demand, Tactical Complexity, lethality, unusual rules or
      technology, broad choice space, dangerous encounters, and unfamiliar settings
      may create beginner friction, but they lower Player Beginner Suitability only to
      the extent that the published playable experience leaves novices without a
      reasonable way to understand what is expected, learn through participation,
      receive useful feedback, or recover and continue.

      Before assigning a score, perform support accounting across expected play:
      1. Identify the material player-facing demands or unfamiliar situations.
      2. Identify authored support that helps novices meet those demands, including
         clear purposes, bounded or legible choices, in-world guidance, explicit
         procedures, demonstrations, feedback, redundant leads, progressive exposure,
         forgiving retries, recovery routes, or progressively broader responsibility.
      3. Assess the residual unsupported beginner burden after that authored support is
         taken into account. Score that residual burden against the AFAO anchors rather
         than scoring the raw difficulty of the challenge itself.

      Authored in-world guidance that is part of substantially-as-published play counts
      as player-facing beginner support even when the GM administers or voices it. Do
      not treat ordinary delivery of published guidance as the "active GM guidance"
      that distinguishes lower anchors. For score 2, active GM guidance means recurring
      special coaching, explanation, rescue, or adaptation beyond what the published
      playable structure already supplies.

      For the 1 ↔ 2 boundary:
      - Score 1 when novices repeatedly lack a reasonable opportunity to understand
        effective participation before serious setbacks, so significant coaching or
        adaptation is ordinarily needed.
      - Score 2 when objectives or immediate choices are usually legible, but recurring
        residual support gaps still make prior experience or special coaching important.
      - Do not assign 1 merely because the adventure is high-level, dangerous,
        mechanically unfamiliar, tactically demanding, or punitive.

      For the 2 ↔ 3 boundary:
      - Score 3 when authored objectives, procedures, guidance, feedback, learning
        loops, or recovery mechanisms make the adventure reasonably learnable through
        participation, even though recurring moments still benefit from prior experience
        or ordinary GM guidance.
      - Score 2 only when recurring friction remains materially unsupported by the
        published playable structure and therefore calls for special coaching beyond it.
      - The presence of demanding rules, unfamiliar technology, dangerous exploration,
        broad scope, or severe consequences does not defeat score 3 when the adventure
        supplies workable authored ways for novices to learn and continue.

      For the 3 ↔ 4 boundary:
      - Score 4 when strong recurring authored support lets novices understand goals,
        navigate choices, learn expected modes of play, and recover from imperfect
        decisions with limited special assistance.
      - Demanding or unfamiliar situations may recur without defeating score 4 when
        those situations are themselves meaningfully scaffolded by the published play.
      - To hold an adventure at score 3, identify recurring residual beginner burdens
        that the publication does not strongly scaffold; do not rely on the mere
        existence of complexity, danger, openness, or unfamiliarity.

      For the 4 ↔ 5 boundary:
      - Score 5 requires a sustained onboarding function across the adventure: the
        playable progression itself repeatedly gives novices clear purposes and
        meaningful choices, supports learning through feedback, redundancy, or
        recovery, and progressively broadens player responsibility.
      - Score 5 does not require perfect safety, trivial encounters, low rules demand,
        linearity, or the absence of traps, dangerous combats, setbacks, or open choices.
        Those features are not automatic vetoes when the overall structure teaches and
        supports novices through them.
      - Score 4 remains appropriate when beginner support is strong and recurring but
        the complete playable structure does not itself sustain that progressive
        onboarding function. Do not promote isolated or phase-limited support to 5.

      In adjacent-anchor falsification, explicitly distinguish a cited challenge from a
      cited support failure. If a lower score depends primarily on raw difficulty while
      authored guidance, feedback, progressive exposure, or recovery materially teaches
      novices how to handle that difficulty, reject that proxy and reassess the residual
      unsupported burden. Conversely, the mere presence of support elements does not
      force a high score: they must materially support ordinary player-facing learning
      across the scope required by the selected anchor.
    TEXT

    # v0.1 remains frozen above as the support-vs-difficulty intervention. v0.2
    # sharpens the 4 ↔ 5 boundary around cumulative, progressively broader
    # novice responsibility without requiring uniform scaffolding of every branch.
    PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_2 = (
      PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_1 + <<~TEXT

        # Player Beginner Suitability 4 ↔ 5 Progressive-Onboarding Clarification v0.2

        For the 4 ↔ 5 boundary, do not interpret "across the adventure,"
        "consistently," or "sustained onboarding" as requiring every encounter,
        route, branch, hazard, or mode of play to be equally scaffolded, explicitly
        taught, forgiving, or self-contained for a novice. Score 5 is an
        adventure-wide structural judgment, not a requirement for uniform local
        tutorial coverage.

        Treat progressively broader player responsibility as positive onboarding
        evidence when the publication first gives novices bounded, legible
        opportunities to learn expected modes of play and then asks them to exercise
        those learned modes with increasing autonomy, scope, combination, or stakes.
        Later openness or difficulty can therefore be evidence that the onboarding
        progression has advanced rather than evidence that onboarding has stopped.

        Evidence for a score-5 onboarding progression includes a recognizable
        cross-adventure sequence in which multiple successive stages:
        - begin from clear immediate purposes or manageable decision contexts;
        - introduce, demonstrate, or provide feedback on expected modes of play;
        - later reuse, combine, or broaden those modes with greater player autonomy;
        - retain enough authored guidance, redundancy, feedback, or recovery that
          imperfect decisions do not routinely break substantive progression.

        Cumulative learning should be meaningfully transferable. Earlier play need not
        explicitly teach later solutions, but the modes, decision habits, feedback, or
        problem-solving expectations novices encounter earlier should remain useful as
        later play broadens and combines them. If later phases principally replace prior
        learning with new bespoke conventions or one-off procedures that novices must
        repeatedly decipher afresh, strong recurring support may still fit score 4
        rather than a sustained score-5 onboarding progression.

        Do not reject score 5 merely because later phases contain dangerous optional
        sites, imperfectly signposted risks, hidden threats, consequential social or
        tactical choices, or less explicit instruction than the opening. Ask whether
        those later demands principally represent broader responsibility built on
        earlier opportunities to learn, while the adventure continues to provide
        legible purposes and workable ways to recover or redirect.

        Weight optional and path-dependent friction according to substantially-as-
        published expected play. A harsh or opaque optional branch defeats score 5
        only when such unsupported demands materially characterize ordinary expected
        progression or when the onboarding trajectory works only on an unusually
        favorable route. Uneven local support by itself is not a score-5 veto.

        # Anti-Inflation Counter-Guardrail

        Strong recurring support is not enough for score 5 unless it forms a
        cumulative progression of novice learning and responsibility across the
        canonical adventure. Repeated quest givers, guides, readable objectives,
        fallback routes, or forgiving scenes may establish score 4 while remaining
        episodic rather than progressively instructional.

        A bounded introductory phase followed by a longer open adventure also does not
        automatically establish score 5. Later phases must materially build on, reuse,
        combine, or broaden modes that novices had prior opportunities to learn while
        continuing enough player-facing support for that increased responsibility to
        be workable. If the publication mainly supplies isolated supports without this
        cross-adventure learning trajectory, score 4 remains appropriate.

        In 4 ↔ 5 adjacent-anchor falsification:
        - To reject 5 in favor of 4, identify where the proposed onboarding progression
          materially breaks: a substantial expected phase should introduce recurring
          new demands for effective participation that neither prior play nor continuing
          authored feedback, guidance, redundancy, or recovery reasonably supports.
          Raw danger, openness, optional difficulty, or uneven branch support is not
          sufficient by itself.
        - To assign 5, identify the cross-adventure progression by which novices first
          learn in more bounded contexts and later exercise broader responsibility. Do
          not rely merely on the number of support elements or on general simplicity.
      TEXT
    ).freeze

    GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # GM Beginner Suitability Application Guardrail v0.1

      When assessing GM Beginner Suitability, measure how well the published adventure
      supports an inexperienced GM in understanding and operating the adventure's actual
      demands. Do not score the raw amount of preparation, improvisation, rules mastery,
      openness, state complexity, encounter difficulty, or judgment that the adventure
      requires. Score how much important GM work remains unsupported after the published
      guidance is taken into account.

      Before assigning a score, perform novice-GM support accounting across ordinary
      substantially-as-published play:
      1. Identify the material GM-facing demands and the central operating tasks needed
         to make expected play function.
      2. Identify authored support for those tasks, including explicit procedures,
         information states, likely reactions, transitions, contingencies, recovery
         guidance, organizational aids, examples, explanations, and direct teaching.
      3. Assess the residual unsupported operating burden after that support is applied.
         Score that residual burden against the AFAO anchors rather than scoring the raw
         difficulty or complexity of the adventure itself.

      # Bookends Are Not an Operating Engine — 1 ↔ 2

      A clear premise, opening, objective, map, NPC roster, encounter list, clues,
      antagonist motives, escape route, or ending does not by itself establish an
      executable default path. Specified content is not automatically specified play.

      Score 1 remains appropriate when ordinary central play still depends on prior GM
      experience to invent a materially important operating engine: for example, how the
      active situation evolves, when and how actors act, how encounters or states are
      generated or sequenced, how central transitions occur, or how the main body of play
      reaches a supported resolution. Authored setup and authored endpoints do not rescue
      a missing central runtime merely because a GM can imagine how to connect them.

      Score 2 is appropriate when the publication supplies a recognizable runnable spine
      for ordinary expected play but leaves recurring or important support gaps that a
      novice is likely to find challenging. Do not require every optional branch,
      connective beat, NPC response, or aftermath to be fully specified in order to
      distinguish 2 from 1.

      Conversely, one weak optional branch, sparse aftermath, or localized omission does
      not force score 1 when the central expected play has a functioning authored engine.
      The missing support must be central or pervasive enough that important ordinary
      play commonly depends on experience-supplied connective or operational work.

      # Authored Resolution vs Implementation Detail — 2 ↔ 3

      For the 2 ↔ 3 boundary, distinguish a missing central resolution from incomplete
      implementation detail around an authored resolution.

      Score 3 can be supported when the publication supplies either a concrete operating
      mechanism for the central situation or a clear condition/action -> defined
      consequential resolution, even though the GM must still synthesize ordinary
      negotiation, connective narration, tactics, presentation, or aftermath around it.
      Do not require every likely conversation, implementation step, reaction, or
      consequence to be exhaustively scripted before the adventure can be Manageable.

      Score 2 remains appropriate when the central resolution itself is materially
      underdefined: the publication identifies actors, motives, goals, or possible
      endpoints but leaves the inexperienced GM to decide what actually constitutes
      success or failure, how the governing situation changes, or what central
      transition makes the adventure proceed or resolve.

      A list of possible actions or outcomes is not automatically an operating
      procedure. Conversely, ordinary GM judgment within a supplied mechanism is not
      automatically evidence that the mechanism is missing.

      # Supported Complexity Is Not a Downward Proxy — 3 ↔ 4

      Size, high character level, unfamiliar technology, numerous NPCs, factions,
      nonlinear structure, state tracking, preparation burden, and improvisational
      latitude can all make an adventure demanding. None of them should hold GM Beginner
      Suitability at 3 when the publication consistently makes those demands actionable
      for a novice through usable procedures, reactions, state handling, contingencies,
      recovery routes, examples, or organization tied to likely trouble spots.

      Score 4 is supported when strong recurring authored guidance operationalizes the
      important situations an inexperienced GM is likely to struggle with, so the GM can
      usually prepare and run successfully without substantial prior experience filling
      central gaps. Difficult execution may remain; the question is whether the source
      tells the novice enough about how to perform it.

      To hold an adventure at score 3 rather than 4, identify recurring central GM tasks
      that remain materially unsupported after the published scaffolding is accounted
      for. Do not rely on the mere presence of complexity, openness, preparation,
      improvisation, high-level mechanics, or discretionary judgment.

      Detailed keying or exact procedures alone do not force score 4. Dense material can
      make an adventure runnable while still assuming substantial technique or synthesis
      from the GM. The support must materially reduce novice uncertainty at recurring
      important operating points, not merely provide more content to absorb.

      # Exceptional Pedagogy Has More Than One Form — 4 ↔ 5

      Score 5 requires positive instructional or scaffolding value beyond merely clear,
      complete, well-organized, or highly runnable material. The publication must
      actively help an inexperienced GM understand what to do, why, and how across
      important GM responsibilities.

      Recognize either of two valid score-5 support architectures when sustained strongly
      enough across the canonical adventure:
      - broad novice-GM teaching combined with adventure-specific operational scaffolds;
        or
      - concentrated adventure-specific procedural teaching that explicitly explains
        how to operate the adventure's important systems, situations, pacing, states,
        contingencies, or recovery paths.

      Direct teaching about how to prepare, improvise, portray NPCs, communicate
      information, track state, recover from mistakes, or manage open play counts as
      beginner support when it gives the novice actionable guidance for performing that
      responsibility. Do not convert the fact that such a responsibility exists into
      evidence against beginner suitability when the publication is actively teaching
      the GM how to handle it.

      Score 5 does not require the adventure to be simple, linear, low-prep,
      low-improvisation, mechanically easy, or free of difficult judgment. A demanding
      adventure can be Exceptionally Supportive when the text exceptionally teaches and
      scaffolds the novice through those demands.

      Preserve score 4 when support is strong and recurring but is primarily clear
      organization, runnable procedures, localized tips, or isolated instructional
      elements rather than an exceptional teaching/scaffolding function across important
      GM responsibilities. The presence of a tracker, flowchart, boxed advice, beginner
      label, or dedicated tips section does not by itself establish score 5.

      # Bidirectional Adjacent-Anchor Falsification

      For every boundary, distinguish a difficult GM task from a published support
      failure. To justify a lower score, identify what important ordinary GM work remains
      unsupported after applicable guidance is accounted for. To justify a higher score,
      identify how the publication actually operationalizes or teaches the relevant GM
      responsibility rather than relying on general clarity, polish, or quantity of
      material.

      Do not presume that this guardrail should raise or lower scores. It clarifies
      application of the frozen AFAO anchors and must preserve both endpoint pressure and
      middle-boundary distinctions.
    TEXT

    # v0.1 remains frozen above as the first GM Beginner Suitability application
    # intervention. v0.2 strengthens decision procedure and boundary preservation
    # without changing the AFAO anchors.
    GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2 = (
      GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_1 + <<~TEXT

        # GM Beginner Suitability Decision Procedure / Boundary Preservation v0.2

        Apply the v0.1 support-accounting rules as a decision procedure, not merely as
        considerations to mention in the rationale. A difficult task that remains for
        the GM to perform is not automatically an unsupported task. The relevant
        question is what guidance the publication fails to provide for performing that
        task successfully.

        # Support-Failure Audit — All Boundaries

        Before using a lower-anchor argument, identify the concrete support failure:
        what important ordinary GM responsibility lacks a usable procedure, decision
        rule, state transition, reaction, example, contingency, recovery path, or
        explanation that an inexperienced GM would materially need. Then explain how
        that absence affects ordinary substantially-as-published play.

        Do not count a responsibility as residual unsupported burden merely because the
        GM must still perform it after reading the adventure. Preparing a chapter,
        choosing among authored options, portraying NPCs, improvising within supplied
        guidance, tracking state, adjudicating rules, or making bounded judgment calls
        can remain demanding while being well supported.

        When a downward argument relies on preparation, improvisation, openness, size,
        state complexity, rules demand, high-level play, numerous NPCs or factions, or
        discretionary judgment, remove that proxy from the argument and ask whether a
        concrete recurring support failure remains. If not, that proxy cannot resolve
        the adjacent boundary downward.

        # Operational Continuity — 1 ↔ 2

        For score 2, a recognizable runnable spine must carry the substantive middle of
        ordinary expected play, not merely connect an authored setup conceptually to
        authored endpoints. Ask how the central situation advances from one playable
        moment or state to the next.

        A premise, threat, roster of actors, locations, clues, goals, possible scenes,
        and resolution conditions can still fit score 1 when the publication leaves the
        GM to invent the central state-evolution mechanism that makes those elements
        operate together during ordinary play.

        Preserve score 2 when the publication does supply an operationally continuous
        central sequence or state mechanism and the remaining omissions are recurring
        but bounded support gaps. Do not require exhaustive scripting of every connective
        beat, optional response, or aftermath.

        # Authored-State Continuity — 2 ↔ 3

        A score-3 operating mechanism can be established by a concrete authored
        condition/action -> defined consequential resolution or by an authored
        state/reaction chain that continues to govern the central situation through its
        resolution. Missing negotiation technique, connective narration, tactical
        detail, implementation prose, or aftermath does not by itself defeat score 3.

        To reject score 3 for score 2 after such a mechanism is identified, name the
        material central state or resolution state that the publication itself leaves
        undefined. Do not merely list ways the GM must execute or present an otherwise
        authored resolution.

        Conversely, the presence of procedures, timers, encounter tables, fixed sites,
        or a sequence of objectives does not force score 3 when the adventure's own
        procedure can ordinarily generate a material central state for which subsequent
        antagonist behavior, progression, or resolution is no longer authored. That
        broken authored-state continuity is a substantive support gap and can preserve
        score 2.

        # Supported-Demand Audit — 3 ↔ 4

        When testing score 3 against 4, pair each cited novice difficulty with the
        support that addresses it before judging the residual burden. Procedures,
        decision rules, state trackers, preparation instructions, examples, likely
        reactions, fallback routes, contingencies, recovery guidance, and explicit
        permission for bounded improvisation all count when they make the difficult
        responsibility actionable.

        The fact that the GM still has to apply that guidance does not recreate the
        support failure. To hold at 3, identify recurring important situations where,
        after this pairing, the inexperienced GM still must supply materially important
        operating knowledge or technique that the publication does not provide.

        # Pedagogical Scope / Upper-Anchor Audit — 4 ↔ 5

        Judge novice-GM teaching by its functional scope, not by how many pages repeat
        it. Concentrated instruction can have adventure-wide pedagogical scope when it
        teaches reusable principles or practices that the publication then expects the
        GM to apply across later play while adventure-specific procedures continue to
        scaffold those applications.

        When the source contains direct novice-GM teaching about multiple important
        responsibilities, explicitly perform the 4 ↔ 5 test even if the adventure is
        large, open, high-prep, improvisational, mechanically demanding, or state-heavy.
        Those demands do not justify stopping the analysis at score 3 when the source
        may actively teach the GM how to handle them.

        This is not automatic score-5 inflation. A tips section, tracker, flowchart, or
        general advice remains insufficient unless the combined teaching and
        adventure-specific scaffolding substantively helps the novice understand what
        to do, why, and how across important responsibilities. Preserve score 4 when
        support is strong but lacks that exceptional pedagogical function.

        # Path-Sensitivity Preservation

        A less-supported authored route does not automatically lower the scalar score.
        Weight the route by its expected and substantive role in ordinary play, then ask
        whether its actual support deficit crosses an anchor boundary. Do not use the
        mere existence of a harder, more improvisational, or less-guided alternative as
        a general downward veto.

        Conversely, do not ignore a weak route when it materially characterizes ordinary
        expected play or when the adventure's support works only on an unusually
        favorable path. Path sensitivity must preserve substantially-as-published
        probability weighting in both directions.
      TEXT
    ).freeze

    # v0.2 remains frozen above. v0.3 adds a narrow adjacent-anchor materiality
    # and coverage-preservation pass for residual-gap overreach.
    GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_3 = (
      GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2 + <<~TEXT

        # GM Beginner Suitability Adjacent-Anchor Materiality / Coverage-Preservation v0.3

        # Anchor-Crossing Materiality Test — All Boundaries

        Identifying an important residual support gap is not by itself sufficient to
        choose the lower adjacent anchor. After identifying the gap, test whether the
        kind, extent, and recurrence of that unsupported burden are actually
        incompatible with the higher anchor.

        Apply the higher anchor's allowed residual burden explicitly. If that anchor
        still permits ordinary judgment, synthesis, bounded omissions, difficult
        execution, incomplete local procedure, or uneven support, the mere presence of
        one of those residual demands cannot independently defeat it. Lower the score
        only when the unsupported residue materially exceeds what the higher anchor
        permits across ordinary substantially-as-published play.

        Do not interpret a higher GM Beginner Suitability anchor as requiring every
        important GM responsibility to be fully proceduralized. This is a coverage and
        materiality test, not a completeness test. Conversely, do not average away a
        central or pervasive support failure merely because many other parts of the
        adventure are well supported.

        In adjacent-anchor falsification, make the boundary decision in this order:
        1. Identify the residual support gap after authored support is credited.
        2. Identify what residual burden the higher adjacent anchor still allows.
        3. Explain whether the cited gap actually exceeds that allowance.
        A lower score must survive step 3; importance of the task or omission alone is
        not enough.

        # Allowed Residual — 1 ↔ 2: Coherent Progression May End in a Major Gap

        Score 2 does not require end-to-end operational continuity through the climax,
        recovery, conclusion, and aftermath. A substantial authored progression that
        carries ordinary play through a meaningful body of the adventure and into the
        central conflict can be enough to escape score 1 even when the handling or
        resolution of that conflict remains a major support gap.

        Preserve score 1 when the missing operating model prevents the publication from
        carrying the substantive central body of ordinary play: setup, actors, goals,
        locations, and endpoints still leave the GM to invent how the main situation
        actually evolves from playable state to playable state.

        Preserve score 2 when the publication itself carries a substantial sequence of
        briefing, travel, investigation, contact, escalation, encounter, or comparable
        progression into the central conflict, while the under-proceduralized handling
        of that conflict is the recurring gap that prevents score 3. Do not move that
        score-2 gap downward into the 1 ↔ 2 boundary by requiring a fully supported
        climax or resolution merely to establish a runnable spine.

        # Allowed Residual — 2 ↔ 3: Authored Resolution Survives Implementation Gaps

        Once a concrete central condition/action -> defined consequential resolution or
        an authored state/reaction chain has been identified, do not relabel ordinary
        implementation gaps as a missing central resolution. Missing narration,
        negotiation technique, tactical execution, enforcement detail, local
        presentation, or aftermath can remain compatible with score 3 when the
        substantive resolution state and its consequential transition are authored.

        To reject 3 for 2 after such a mechanism is identified, name the substantive
        resolution state, governing transition, or continuing central state that remains
        undefined. The fact that the GM must decide how to present, negotiate,
        adjudicate, or execute an authored transition does not by itself cross the
        boundary.

        Likewise, do not treat every mentioned player method as a coequal authored route
        that must receive independent procedural completeness. A less-supported method
        becomes a route-level reason to reject 3 only when the publication materially
        structures it as an expected substantive pathway and its unsupported operation
        materially characterizes ordinary play.

        This clarification does not force score 3 from the mere presence of procedures.
        Preserve score 2 when the adventure's own procedure can generate a material
        central state for which subsequent progression, antagonist behavior, or
        resolution is genuinely unauthored.

        # Allowed Residual — 3 ↔ 4: Consistent Support Is Not Exhaustive Support

        "Consistent" operational support at score 4 does not mean that every important
        scene, NPC response, force quantity, presentation choice, faction interaction,
        or discretionary judgment is specified. Localized execution choices and bounded
        calls for GM technique can remain compatible with score 4 when the publication
        repeatedly supplies the state transitions, reactions, branch continuations,
        contingencies, recovery mechanisms, or decision support needed to keep ordinary
        play coherent.

        To reject 4 for 3, the unsupported residue must recur with enough operational
        consequence that an inexperienced GM regularly lacks support for preserving
        coherent state, progression, consequential response, or recovery across ordinary
        expected play. Do not reject 4 merely by accumulating important scenes in which
        the GM still exercises judgment or supplies presentation detail.

        Multiple localized gaps may collectively cross the boundary when they repeatedly
        leave a central mode of play without usable operating support. The clarification
        preserves that downward pressure; it only prevents "not everything important is
        proceduralized" from becoming an implicit score-4 veto.

        # Allowed Residual — 4 ↔ 5: Pedagogy May Be Compositional and Transferable

        For score 5, broad reusable novice-GM instruction and distributed
        adventure-specific scaffolding may satisfy the what/why/how pedagogical test
        together. They need not be co-located, repeated beside every later application,
        or explicitly cross-referenced. Teaching a reusable principle once can provide
        the "how" for later responsibilities when the adventure subsequently supplies
        the concrete states, procedures, trackers, reactions, contingencies, or
        preparation guidance through which that principle is applied.

        Do not treat the novice's continued need to synthesize a campaign, portray NPCs,
        manage open play, maintain callbacks, prepare upcoming material, or exercise
        judgment as evidence against score 5 merely because those tasks remain real.
        They defeat 5 only when an important class of defining GM responsibility
        repeatedly lacks both meaningful reusable teaching and adventure-specific
        scaffolding, leaving the novice without the exceptional support required by the
        anchor.

        Preserve score 4 when general advice plus clear procedures remain primarily
        useful organization or isolated tips rather than an exceptional combined
        teaching/scaffolding architecture. Compositional pedagogy is not automatic
        score-5 inflation; the combined support must materially teach and scaffold the
        defining responsibilities of ordinary play.
      TEXT
    ).freeze

    # v0.3 is retained above as a rejected calibration experiment. v0.4 deliberately
    # branches from the last stable v0.2 control rather than inheriting v0.3. It adds
    # only lower-boundary structural clarification for 1 ↔ 2 and 2 ↔ 3.
    GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4 = (
      GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_2 + <<~TEXT

        # GM Beginner Suitability Lower-Boundary Structural Clarification v0.4

        Apply this clarification only to the 1 ↔ 2 and 2 ↔ 3 boundaries. It does not
        modify the v0.2 rules for 3 ↔ 4, 4 ↔ 5, or path-sensitivity weighting.

        # Playable-State Generation / Progression Shape — 1 ↔ 2

        To escape score 1, the publication must carry a substantial body of central
        ordinary play through at least one of two executable architectures:

        1. Authored sequential progression: the publication supplies successive
           playable states or transitions that substantially carry the GM through the
           central body of play; or
        2. Authored runtime/state mechanism: a procedure, state engine, encounter rule,
           reaction chain, or comparable operating mechanism determines or generates
           how central play advances from one playable state to another.

        These architectures are alternatives, not cumulative requirements. A runtime
        mechanism need not form a conventional scene sequence, and a sequential spine
        need not supply a separate state engine.

        A conceptual sequence is not enough. Setup -> threat or objective -> named
        actors or locations -> possible resolution does not establish score 2 when the
        publication still leaves the GM to invent how the substantive middle evolves
        from playable state to playable state. Story facts, motives, encounter contents,
        and endpoints do not become executable progression merely because a capable GM
        can connect them.

        Conversely, do not require the score-2 architecture to remain operationally
        complete through the final climax, recovery, conclusion, or aftermath. A
        substantial authored sequence can carry ordinary play into the central conflict
        and still leave that conflict under-proceduralized; that later support gap can
        be the reason the adventure remains score 2 rather than 3 without collapsing
        the earlier executable progression down to score 1.

        Likewise, do not reject score 2 merely because a procedural runtime is sparse
        in connective presentation. When an authored mechanism actually generates or
        determines central encounters, states, reactions, or transitions, count that as
        executable play even if the GM must supply description, local connective tissue,
        or ordinary implementation detail around the generated states.

        In 1 ↔ 2 adjacent-anchor falsification, identify which executable architecture
        carries the substantive middle. Assign 1 when neither authored sequential
        progression nor an authored runtime/state mechanism substantially carries
        central ordinary play. Assign 2 when at least one does, while preserving the
        possibility that major later support gaps keep the adventure from score 3.

        # Authored Path vs Player Method — 2 ↔ 3

        When a concrete central condition/action -> consequential resolution or an
        authored state/reaction mechanism establishes the central resolution structure,
        do not treat every mentioned, permitted, or naturally available player method
        for reaching or implementing that resolution as a separate authored pathway.

        A player method becomes a route-level support obligation only when the
        publication materially structures it as a distinct authored body of play—for
        example through route-specific progression, states, procedures, consequences,
        encounters, or transitions substantial enough that ordinary play is expected to
        follow that authored alternative as a pathway rather than merely attempt a
        different technique inside the same governing situation.

        Mentioned or foreseeable approaches such as negotiation, stealth, force,
        deception, investigation, or improvisational social handling do not by
        themselves create coequal authored routes whose incomplete scripting defeats
        score 3. Missing technique for presenting, adjudicating, negotiating, fighting,
        sneaking, or enforcing an otherwise authored transition remains implementation
        detail unless the omission leaves the substantive resolution state or governing
        central transition itself undefined.

        Preserve score 2 when the publication truly authors a substantive alternative
        pathway whose central operation is materially unsupported, or when the governing
        resolution/state mechanism itself breaks and leaves a consequential central
        state unauthored. Do not promote to 3 merely because one supported method exists
        if ordinary expected play materially depends on a separately authored but
        unsupported route.

        In 2 ↔ 3 adjacent-anchor falsification, first identify the governing central
        resolution or state mechanism. Then distinguish implementation methods inside
        that mechanism from separately authored pathways. Reject score 3 only when the
        missing support belongs to the governing central state/resolution itself or to a
        materially structured authored pathway that substantially characterizes ordinary
        expected play.
      TEXT
    ).freeze

    # v0.4 remains frozen above as the best lower-boundary control. v0.5 adds one
    # final bounded upper-anchor experiment for 4 ↔ 5 only.
    GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_5 = (
      GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_4 + <<~TEXT

        # GM Beginner Suitability Exceptional-Pedagogy Decision Audit v0.5

        Apply this clarification only to the 4 ↔ 5 boundary. It does not modify the
        v0.4 rules for 1 ↔ 2 or 2 ↔ 3, the v0.2 rule for 3 ↔ 4, or path-sensitivity
        weighting. This is not a general instruction to choose score 5.

        The v0.1 guardrail recognizes two valid score-5 support architectures:
        broad novice-GM teaching combined with adventure-specific scaffolding, and
        concentrated adventure-specific procedural teaching. Keep both architectures
        available. The audit below makes the first architecture easier to recognize
        without narrowing the second.

        # Teaching-to-Application Pairing — Broad-Instruction Architecture

        When the publication contains broad novice-GM instruction, assess the teaching
        and the later adventure-specific scaffolding as one functional system rather
        than asking whether every later task repeats its own tutorial.

        Build an evidence pairing across several materially different GM
        responsibilities:
        - Teaching evidence: direct novice-oriented guidance that explains how or why
          to perform the responsibility, supplies a reusable decision principle, or
          otherwise teaches technique rather than merely stating adventure content.
        - Application evidence: procedures, preparation instructions, trackers,
          information-state guidance, reaction models, examples, pacing or transition
          rules, contingencies, recovery guidance, or bounded-improvisation support
          that helps the GM apply that teaching in ordinary play.

        The two halves of a pair need not be co-located, repeated beside every later
        application, or explicitly cross-referenced. A reusable principle taught once
        can support later applications when the publication supplies concrete
        adventure-specific structures through which that principle is exercised.
        Count breadth by materially different GM responsibilities, not by the number of
        artifacts that support the same responsibility.

        Treat the broad-instruction architecture as affirmative score-5 evidence when
        several materially different responsibilities receive genuine teaching and
        the adventure repeatedly supplies usable application scaffolds for those
        responsibilities across ordinary substantially-as-published play. In that
        circumstance, the novice's continued need to read ahead, synthesize state,
        portray NPCs, improvise within guidance, prepare upcoming material, or exercise
        judgment does not by itself show that exceptional pedagogy is absent. The
        teaching is successful when it equips the novice to perform those tasks; it
        need not eliminate the tasks.

        # Concentrated Procedural Teaching Preservation

        Do not require broad general GM instruction in order to assign score 5. The
        concentrated adventure-specific architecture recognized by v0.1 remains valid
        when the publication itself repeatedly explains how to operate its important
        systems, situations, pacing, states, contingencies, or recovery paths in a way
        that actively teaches the inexperienced GM rather than merely documenting
        content. v0.5 must preserve that independent route to the upper anchor.

        # Anti-Inflation Counter-Guardrail — Preserve Strong 4s

        Strong organization, runnable procedures, trackers, clear objectives, fallback
        routes, forgiving design, boxed advice, or abundant GM-facing detail do not
        establish score 5 by themselves. Those elements can make an adventure highly
        supportive while remaining score 4 when they primarily tell the GM what the
        adventure contains or what happens next rather than teaching reusable how/why
        principles or adventure-specific operating technique.

        Likewise, direct GM advice does not establish score 5 when it is isolated,
        generic, limited to one narrow responsibility, or functionally disconnected
        from the recurring adventure-specific scaffolds used in ordinary play. Teaching
        without meaningful application support can remain score 4; application
        scaffolding without meaningful teaching can remain score 4.

        In 4 ↔ 5 adjacent-anchor falsification:
        - To assign 5 through the broad-instruction architecture, identify several
          materially different responsibilities with genuine teaching evidence and
          show how recurring adventure-specific scaffolds support application of that
          teaching across ordinary play.
        - To reject 5 for 4, identify the missing pedagogical function: insufficient
          breadth of genuine teaching, teaching that supplies little actionable
          how/why, or application scaffolding too isolated to make the teaching
          operational across important responsibilities.
        - Do not reject 5 solely because substantial GM work remains. Reject it because
          the publication does not exceptionally teach and scaffold how to perform that
          work.
      TEXT
    ).freeze

    GM_PREPARATION_BURDEN_GUARDRAIL_V0_1 = <<~TEXT.freeze
      # GM Preparation Burden Application Guardrail v0.1

      When assessing GM Preparation Burden, measure the pre-play work the GM
      ordinarily must perform to run the canonical adventure effectively. Do not
      infer burden merely from the number of facts, procedures, scenes, NPCs, or
      pages that exist; assess what advance work those elements actually require.

      # Localized-Read Rule — 1 ↔ 2

      Score 1 does not mean zero preparation or a literal skim that can ignore
      important details. A brief attentive read may include several compact,
      co-located NPC facts, encounter instructions, small tables, unusual creature
      behaviors, or minor rules lookups and still remain Minimal when absorbing that
      localized material is essentially the preparation and little synthesis,
      cross-referencing, note-making, or advance decision-making is needed.

      Do not reject score 1 solely because the GM must consciously understand more
      than one small procedure or because a careless skim would be insufficient.
      Score 2 begins when effective play ordinarily benefits from light preparation
      beyond that immediate attentive read, such as deliberate whole-unit familiarity,
      modest encounter review, small notes, or light advance organization.

      # Authored-Sequence Rule — 2 ↔ 3

      Do not promote score 2 to score 3 merely because clues, NPCs, callbacks,
      developments, or locations occur across several sequential scenes. Information
      distributed across an explicitly authored chain is not automatically an
      "interacting element" that requires meaningful synthesis.

      When the publication supplies the expected progression, clue connections,
      fallbacks, transitions, and localized keyed encounters, understanding that
      sequence may remain Low preparation if the GM can obtain the needed readiness
      mainly by reading through it with only light notes or organization.

      Score 3 begins when the GM must perform meaningful advance preparation: for
      example, review significant upcoming material, organize genuinely interacting
      elements, repeatedly master precision-sensitive mechanisms, or have several
      substantive alternatives ready before the players select among them. Several
      materially different upcoming alternatives can establish Moderate burden even
      when each alternative is clearly written and cleanly compartmentalized.

      # Organization-Is-Not-Prep-Reduction Rule — 3 ↔ 4 ↔ 5

      Clear writing, dedicated sections, flowcharts, tables, or other publisher
      organization can make required preparation easier to perform, but they do not
      erase the amount or dependency structure of the preparation itself. Do not hold
      an adventure at score 3 merely because substantial states, dependencies,
      branches, revelations, or advance tasks are clearly organized.

      Score 4 begins when the GM must absorb or coordinate enough relevant material,
      dependencies, states, or advance tasks that relying primarily on a short
      pre-session read becomes unreliable. Score 4 does not require extensive
      reconstruction, campaign-wide mastery, sustained tracking infrastructure, or a
      campaign-management layer; those are upper-boundary signals that help
      distinguish score 5 from score 4.

      Conversely, good organization does not force score 4: the underlying pre-play
      work must still be substantial. Preserve score 3 when preparation is meaningful
      but bounded and manageable without the amount of advance absorption or
      coordination required by the High anchor.

      In adjacent-anchor falsification, identify the actual pre-play work required and
      test that work against both neighboring anchors. Do not use "more than a skim,"
      authored scene count, clear organization, or absence of campaign-scale
      infrastructure as a standalone boundary test. Keep runtime invention and
      adjudication in GM Improvisation Demand and GM experience requirements in GM
      Beginner Suitability.
    TEXT

    # v0.1 remains frozen above as the first GM Preparation Burden application
    # intervention. v0.2 adds counter-guardrails for the 1 ↔ 2, 3 ↔ 4, and
    # 4 ↔ 5 boundaries exposed by the first production baseline retest.
    GM_PREPARATION_BURDEN_GUARDRAIL_V0_2 = (
      GM_PREPARATION_BURDEN_GUARDRAIL_V0_1 + <<~TEXT

        # GM Preparation Burden Boundary Counter-Guardrails v0.2

        # Compact Whole-Unit Read Clarification — 1 ↔ 2

        For a compact canonical unit, the immediately relevant material may be
        essentially the whole adventure. Do not promote score 1 to score 2 merely
        because an attentive GM should read that whole short unit, understand every
        small NPC motive or procedure in it, or consult a few localized tables,
        stat blocks, or shared rules before play.

        When one brief attentive pass through the compact operational material itself
        creates sufficient readiness, that reading is the preparation and can remain
        Minimal. Calling the same pass a "deliberate whole-unit read," "encounter
        review," or "careful review" does not by itself establish additional Low
        preparation burden.

        To assign score 2 over score 1, identify what light preparation is ordinarily
        useful or expected beyond simply absorbing that compact localized material—for
        example, familiarity that must span separated scenes or dependencies, a useful
        second-pass encounter review, small notes, or light advance organization. The
        mere fact that a careless skim would be insufficient is not enough.

        # Precision-Sensitive Bounded-Site Clarification — 3 ↔ 4

        The fact that a GM cannot reliably read only the next room, encounter, or
        immediate scene does not by itself establish score 4. Apply the High anchor's
        "short pre-session read becomes unreliable" language to substantial overall
        advance preparation, not merely to the need for careful familiarity with a
        bounded nonlinear or precision-sensitive keyed site.

        Exact traps, hidden routes, teleporters, false information, keyed mechanisms,
        neutral-referee presentation, or other precision-sensitive procedures can make
        meaningful advance review necessary while remaining score 3 when the work is
        bounded, localized in usable keyed material, and manageable without substantial
        organization or broad mastery.

        Several substantive alternatives can establish score 3 without automatically
        creating score 4. When the publication lets the table fix a destination or
        route with enough separation for the GM to prepare that selected, largely
        self-contained material before it is run, do not accumulate every unselected
        alternative as though it must remain fully ready.

        To assign score 4 to a bounded or partitionable structure, identify the
        substantial preparation body beyond precision or alternative count alone: for
        example, a significant breadth of player-selectable material that must actually
        be ready before selection, many interacting states or dependencies, broad
        cross-location coordination, or substantial organizational work. Do not turn
        "several possible nearby routes require prior familiarity" into an automatic
        High-preparation rule.

        # Sustained Campaign-Management Clarification — 4 ↔ 5

        In the 4 ↔ 5 boundary, "preparation infrastructure or sustained advance
        mastery" is a functional description of ongoing preparation burden. Score 5
        does not require a bespoke tracking artifact, extensive reconstruction,
        simultaneous mastery of every possible path, or preparation of mutually
        exclusive branches as though they will all occur.

        Score 4 remains appropriate when substantial preparation can be partitioned
        into bounded sites, chapters, or publisher-supported segments that can be
        prepared largely independently once the relevant segment is known. Carrying a
        compact tracker or a limited set of callbacks across an otherwise ordered
        sequence does not by itself establish score 5.

        Score 5 can be supported when ordinary play repeatedly requires an ongoing
        campaign-management layer: maintaining broad cross-campaign context or state,
        choosing and organizing the relevant next preparation from a wide active field
        of destinations, quests, factions, or route bodies, cross-referencing earlier
        choices with later preparation, and sustaining that work across many sessions.
        The GM may still prepare only the selected and likely next material at any one
        time; the Very High burden can arise from the recurring campaign-scale work of
        determining, contextualizing, and organizing that material.

        Clear chapters, keyed locations, route-specific sections, published trackers,
        and explicit transitions may reduce the labor involved, but they do not cap an
        adventure at score 4 if they support rather than eliminate an ongoing
        campaign-management burden. Conversely, do not assign score 5 from length,
        number of hypothetical branches, or a claim that all possible content must be
        ready simultaneously. Identify the sustained cross-campaign preparation work
        that ordinary substantially-as-published play actually requires.
      TEXT
    ).freeze

    # v0.2 remains frozen above. v0.3 is a narrow boundary-preservation pass
    # for proxy errors exposed by the second production retest.
    GM_PREPARATION_BURDEN_GUARDRAIL_V0_3 = (
      GM_PREPARATION_BURDEN_GUARDRAIL_V0_2 + <<~TEXT

        # GM Preparation Burden Boundary Preservation v0.3

        Apply these clarifications only to the specific adjacent-boundary tests below.
        They do not alter the Minimal endpoint established by the prior 1 ↔ 2 rules.

        # Pre-Selection Readiness — 2 ↔ 3

        The ability to defer full execution preparation until after a player choice does
        not erase preparation that is ordinarily needed before that choice. When the GM
        must understand several substantive alternatives well enough to present their
        distinct premises, destinations, procedures, or consequences before selection,
        that pre-selection readiness can itself be meaningful Moderate preparation even
        though only the chosen alternative receives full encounter-by-encounter prep.

        Preserve score 2 when apparent alternatives are minor variations or when a
        strongly authored progression ordinarily leaves only one bounded sequence
        requiring meaningful readiness at a time. Do not require every alternative to
        be fully prepared simultaneously in order for several substantive alternatives
        to support score 3.

        # Cross-Cutting Bounded Structure — 3 ↔ 4

        "Bounded" and "partitionable" are operational, not merely geographic. A keyed
        site is not automatically score 3 when cross-cutting states, selected scenario
        tracks, staged information, prepared events, or climax dependencies must be
        understood together before open play and materially alter how many locations or
        later scenes are run. Those dependencies can create substantial High preparation
        even when the publication supplies a flowchart, centralized procedures, and one
        compact site.

        Conversely, preserve score 3 when the advance work is chiefly careful route,
        map, or precision-sensitive mechanism familiarity within otherwise localized
        keyed material. Precision and nonlinear routing alone still do not establish
        substantial cross-cutting preparation.

        # Ordered Stages vs Campaign Management — 4 ↔ 5

        Persistent callbacks, a tracker, or open navigation inside successive bounded
        regions do not by themselves create the ongoing campaign-management layer needed
        for score 5. Score 4 remains available when authored progression materially
        narrows the active preparation field to the current chapter or region and most
        future bodies can wait until that stage becomes relevant, even if some state is
        carried forward across stages.

        This does not narrow the existing score-5 test. Retain Very High when ordinary
        play repeatedly requires selecting and contextualizing the next preparation from
        a wide active campaign-level field while carrying earlier state across many
        sessions. As in v0.2, score 5 does not require simultaneous mastery of every path.
      TEXT
    ).freeze

    # v0.1-v0.3 remain frozen above as the historical lower/middle-boundary
    # calibration record. v0.4 and v0.5 were experimental construction stages
    # and are intentionally absent from the production runtime path.
    #
    # v0.6 is stored as the exact qualified runtime snapshot so cleanup cannot
    # alter a single scorer-facing byte while removing the rejected mutation chain.
    GM_PREPARATION_BURDEN_GUARDRAIL_V0_6 = (
      <<~'GMPB_V0_6_QUALIFIED_SNAPSHOT'
        # GM Preparation Burden Application Guardrail v0.1

        When assessing GM Preparation Burden, measure the pre-play work the GM
        ordinarily must perform to run the canonical adventure effectively. Do not
        infer burden merely from the number of facts, procedures, scenes, NPCs, or
        pages that exist; assess what advance work those elements actually require.

        # Localized-Read Rule — 1 ↔ 2

        Score 1 does not mean zero preparation or a literal skim that can ignore
        important details. A brief attentive read may include several compact,
        co-located NPC facts, encounter instructions, small tables, unusual creature
        behaviors, or minor rules lookups and still remain Minimal when absorbing that
        localized material is essentially the preparation and little synthesis,
        cross-referencing, note-making, or advance decision-making is needed.

        Do not reject score 1 solely because the GM must consciously understand more
        than one small procedure or because a careless skim would be insufficient.
        Score 2 begins when effective play ordinarily benefits from light preparation
        beyond that immediate attentive read, such as deliberate whole-unit familiarity,
        modest encounter review, small notes, or light advance organization.

        # Authored-Sequence Rule — 2 ↔ 3

        Do not promote score 2 to score 3 merely because clues, NPCs, callbacks,
        developments, or locations occur across several sequential scenes. Information
        distributed across an explicitly authored chain is not automatically an
        "interacting element" that requires meaningful synthesis.

        When the publication supplies the expected progression, clue connections,
        fallbacks, transitions, and localized keyed encounters, understanding that
        sequence may remain Low preparation if the GM can obtain the needed readiness
        mainly by reading through it with only light notes or organization.

        Score 3 begins when the GM must perform meaningful advance preparation: for
        example, review significant upcoming material, organize genuinely interacting
        elements, repeatedly master precision-sensitive mechanisms, or have several
        substantive alternatives ready before the players select among them. Several
        materially different upcoming alternatives can establish Moderate burden even
        when each alternative is clearly written and cleanly compartmentalized.

        # Organization-Is-Not-Prep-Reduction Rule — 3 ↔ 4 ↔ 5

        Clear writing, dedicated sections, flowcharts, tables, or other publisher
        organization can make required preparation easier to perform, but they do not
        erase the amount or dependency structure of the preparation itself. Do not hold
        an adventure at score 3 merely because substantial states, dependencies,
        branches, revelations, or advance tasks are clearly organized.

        Score 4 begins when the GM must absorb or coordinate enough relevant material,
        dependencies, states, or advance tasks that relying primarily on a short
        pre-session read becomes unreliable. Once score 4 is established, decide 4 ↔ 5
        only with the explicit upper-boundary procedure below. Scope, boundedness, and
        absence of campaign-scale structure are not downward evidence at that boundary.

        Conversely, good organization does not force score 4: the underlying pre-play
        work must still be substantial. Preserve score 3 when preparation is meaningful
        but bounded and manageable without the amount of advance absorption or
        coordination required by the High anchor.

        In adjacent-anchor falsification, identify the actual pre-play work required and
        test that work against both neighboring anchors. Do not use "more than a skim,"
        authored scene count, clear organization, or absence of campaign-scale
        infrastructure as a standalone boundary test. Keep runtime invention and
        adjudication in GM Improvisation Demand and GM experience requirements in GM
        Beginner Suitability.

        # GM Preparation Burden Boundary Counter-Guardrails v0.2

        # Compact Whole-Unit Read Clarification — 1 ↔ 2

        For a compact canonical unit, the immediately relevant material may be
        essentially the whole adventure. Do not promote score 1 to score 2 merely
        because an attentive GM should read that whole short unit, understand every
        small NPC motive or procedure in it, or consult a few localized tables,
        stat blocks, or shared rules before play.

        When one brief attentive pass through the compact operational material itself
        creates sufficient readiness, that reading is the preparation and can remain
        Minimal. Calling the same pass a "deliberate whole-unit read," "encounter
        review," or "careful review" does not by itself establish additional Low
        preparation burden.

        To assign score 2 over score 1, identify what light preparation is ordinarily
        useful or expected beyond simply absorbing that compact localized material—for
        example, familiarity that must span separated scenes or dependencies, a useful
        second-pass encounter review, small notes, or light advance organization. The
        mere fact that a careless skim would be insufficient is not enough.

        # Precision-Sensitive Bounded-Site Clarification — 3 ↔ 4

        The fact that a GM cannot reliably read only the next room, encounter, or
        immediate scene does not by itself establish score 4. Apply the High anchor's
        "short pre-session read becomes unreliable" language to substantial overall
        advance preparation, not merely to the need for careful familiarity with a
        bounded nonlinear or precision-sensitive keyed site.

        Exact traps, hidden routes, teleporters, false information, keyed mechanisms,
        neutral-referee presentation, or other precision-sensitive procedures can make
        meaningful advance review necessary while remaining score 3 when the work is
        bounded, localized in usable keyed material, and manageable without substantial
        organization or broad mastery.

        Several substantive alternatives can establish score 3 without automatically
        creating score 4. When the publication lets the table fix a destination or
        route with enough separation for the GM to prepare that selected, largely
        self-contained material before it is run, do not accumulate every unselected
        alternative as though it must remain fully ready.

        To assign score 4 to a bounded or partitionable structure, identify the
        substantial preparation body beyond precision or alternative count alone: for
        example, a significant breadth of player-selectable material that must actually
        be ready before selection, many interacting states or dependencies, broad
        cross-location coordination, or substantial organizational work. Do not turn
        "several possible nearby routes require prior familiarity" into an automatic
        High-preparation rule.

        # GM Preparation Burden Boundary Preservation v0.3

        Apply these clarifications only to the specific adjacent-boundary tests below.
        They do not alter the Minimal endpoint established by the prior 1 ↔ 2 rules.

        # Pre-Selection Readiness — 2 ↔ 3

        The ability to defer full execution preparation until after a player choice does
        not erase preparation that is ordinarily needed before that choice. When the GM
        must understand several substantive alternatives well enough to present their
        distinct premises, destinations, procedures, or consequences before selection,
        that pre-selection readiness can itself be meaningful Moderate preparation even
        though only the chosen alternative receives full encounter-by-encounter prep.

        Preserve score 2 when apparent alternatives are minor variations or when a
        strongly authored progression ordinarily leaves only one bounded sequence
        requiring meaningful readiness at a time. Do not require every alternative to
        be fully prepared simultaneously in order for several substantive alternatives
        to support score 3.

        # Cross-Cutting Bounded Structure — 3 ↔ 4

        "Bounded" and "partitionable" are operational, not merely geographic. A keyed
        site is not automatically score 3 when cross-cutting states, selected scenario
        tracks, staged information, prepared events, or climax dependencies must be
        understood together before open play and materially alter how many locations or
        later scenes are run. Those dependencies can create substantial High preparation
        even when the publication supplies a flowchart, centralized procedures, and one
        compact site.

        Conversely, preserve score 3 when the advance work is chiefly careful route,
        map, or precision-sensitive mechanism familiarity within otherwise localized
        keyed material. Precision and nonlinear routing alone still do not establish
        substantial cross-cutting preparation.


        # GM Preparation Burden 4 ↔ 5 Dependency-Fan-Out Procedure v0.6

        Apply this procedure only after score 4 has already been established under the
        lower and middle-boundary rules above. Preserve those rules unchanged.

        The 4 ↔ 5 distinction turns on the breadth and persistence of the preparation
        dependencies the GM must manage across the authored material. Do not equate the
        amount of information needed to RECORD a state with the amount of preparation
        needed to USE that state correctly.

        # Step 1 — Identify persistent preparation inputs

        Identify state, access conditions, relationships, clocks, alerts, discoveries,
        route permissions, altered locations, roaming consequences, objective progress,
        cross-references, or other information that can remain relevant after the unit
        where it first appears.

        # Step 2 — Evaluate dependency fan-out

        Ask how broadly each persistent input changes later preparation. Relevant effects
        include changing:
        - which later material is accessible or likely to be selected;
        - how later keyed locations, encounters, NPCs, or procedures should be interpreted;
        - which prior facts, locations, or systems must be cross-referenced;
        - what the GM must update, coordinate, anticipate, or remember before later play;
        - how later objectives, transitions, encounters, or end-state conditions operate.

        A state variable can be compact to write down and still have broad preparation
        fan-out. A number, checklist, key list, short tracker, or publisher-provided
        worksheet is not evidence that preparation is meaningfully partitionable when
        applying that recorded state requires the GM to integrate it across a large or
        unusually interconnected body of later material.

        # Score 4

        Favor score 4 when substantial preparation can still be divided into bounded
        upcoming units because persistent inputs have limited or localized fan-out.
        Carry-forward information may matter, but applying it ordinarily requires only
        a small number of direct updates, callbacks, or local adjustments. Most later
        material can therefore be understood and prepared without sustained
        cross-referencing or coordination across a broad active dependency structure.

        # Score 5

        Score 5 can be appropriate when effective play ordinarily requires sustained
        advance mastery, tracking, cross-referencing, or organization across a large or
        unusually interconnected body because one or more persistent inputs have broad
        material consequences across otherwise separable units. The qualifying burden is
        the ongoing integration work: later preparation repeatedly depends on relating
        current state or prior developments to many locations, routes, encounters,
        procedures, objectives, or end-state conditions.

        Score 5 does NOT require every prior detail to remain active, all possible future
        content to be prepared simultaneously, or the carried state itself to be lengthy.
        Compact representation does not cap the score when dependency fan-out remains
        broad and materially affects later preparation.

        # Invalid downward evidence at 4 ↔ 5

        Do not use any of the following as evidence for score 4 or against score 5:
        - that the canonical unit is one adventure, one dungeon, one site, or one location;
        - that it is bounded, self-contained, geographically compact, or clearly divided
          into chapters, sectors, regions, or keyed locations;
        - that a publisher supplies clear keying, a tracker, a table, a map, a flowchart,
          or centralized procedures;
        - that a persistent state can be represented by a small number, short list, or
          compact note;
        - that the adventure lacks multiple cities, broad geographic scope, multiple
          campaign arcs, a wide active field, or campaign-scale management.

        Those properties can reduce labor only when they actually reduce dependency
        fan-out or the cross-referencing, coordination, and advance understanding required
        to apply the persistent state across later material.

        # Anti-inflation

        Length, page count, room count, map complexity, branch count, a tracker, a
        persistent counter, or cross-unit state alone does not establish score 5.
        Broad fan-out must create actual ordinary advance-preparation work. A large
        adventure remains score 4 when its upcoming units are substantially independent
        and carry-forward state produces only bounded local adjustments.

        # Adjacent-anchor output discipline

        If the assigned score is 4, adjacent_lower_reason must explain why the evidence
        exceeds score 3, and adjacent_higher_reason must identify why persistent
        preparation inputs have sufficiently limited/localized fan-out that the adventure
        does not reach score 5. If the assigned score is 5, adjacent_lower_reason must
        identify the broad cross-unit dependency fan-out that makes ordinary score-4
        partitioning inadequate.
      GMPB_V0_6_QUALIFIED_SNAPSHOT
    ).freeze

    Prompt = Struct.new(:instructions, :input, keyword_init: true)

    def initialize(afao:, assessment_spec:)
      @afao = afao
      @assessment_spec = assessment_spec
    end

    def build(group_name:, adventure:, source_extraction:, dimensions: nil, levels_context: nil)
      group_dimensions = DimensionGroups.fetch(group_name)
      dimensions ||= group_dimensions
      unknown = dimensions - group_dimensions
      unless unknown.empty?
        raise SpecificationError, "Dimensions not in #{group_name}: #{unknown.join(', ')}"
      end

      rubric = if dimensions == group_dimensions
                 @afao.rubric_for_group(
                   group_name,
                   target_id: adventure.id,
                   target_title: adventure.title
                 )
               else
                 @afao.rubric_for_dimensions(
                   dimensions,
                   target_id: adventure.id,
                   target_title: adventure.title
                 )
               end
      if dimensions == ["# of Sessions"]
        return build_nos_prompt(
          adventure: adventure,
          source_extraction: source_extraction,
          rubric: rubric
        )
      end
      if dimensions == ["Exploration Emphasis"]
        return build_qualified_ee_prompt(
          adventure: adventure,
          source_extraction: source_extraction,
          rubric: rubric
        )
      end
      if dimensions == ["GM Beginner Suitability"]
        return build_blind_gmbs_prompt(
          adventure: adventure,
          source_extraction: source_extraction,
          rubric: rubric
        )
      end
      if dimensions.include?("# of Sessions")
        raise SpecificationError, "# of Sessions must be scored independently from Levels"
      end

      Prompt.new(
        instructions: SYSTEM_INSTRUCTIONS,
        input: <<~PROMPT
          # Canonical Target

          Adventure ID: #{adventure.id}
          Adventure Title: #{adventure.title}
          Source Book: #{adventure.source_book}
          Book Publisher: #{adventure.publisher}
          Canonical Start Page: #{adventure.start_page}
          Canonical End Page: #{adventure.end_page}
          Source Scope Supplied: #{source_extraction.scope}
          Source File: #{source_extraction.source_file}

          The source body below is the evidence basis for the canonical target. Page markers are evidence locators.
          Material outside the canonical Adventure ID must not be allowed to contaminate the assessment.

          # Published Source Material

          #{source_extraction.text}
          #{levels_context_block(dimensions, levels_context)}

          # AdventureFinder Production Assessment Rules

          #{@assessment_spec.prompt_text}

          # AFAO #{ @afao.version } Rubric for This Focused Pass

          #{rubric}#{levels_guardrail_block(dimensions)}#{combat_guardrail_block(dimensions)}#{investigation_emphasis_guardrail_block(dimensions)}#{puzzle_problem_solving_emphasis_guardrail_block(dimensions)}#{social_interaction_emphasis_guardrail_block(dimensions)}#{fantastic_weirdness_guardrail_block(dimensions)}#{seriousness_guardrail_block(dimensions)}#{darkness_horror_intensity_guardrail_block(dimensions)}#{structural_openness_guardrail_block(dimensions)}#{consequential_player_agency_guardrail_block(dimensions)}#{lethality_failure_severity_guardrail_block(dimensions)}#{rules_system_mastery_demand_guardrail_block(dimensions)}#{gm_preparation_burden_guardrail_block(dimensions)}#{gm_improvisation_demand_guardrail_block(dimensions)}#{player_beginner_suitability_guardrail_block(dimensions)}#{gm_beginner_suitability_guardrail_block(dimensions)}

          # Focused Assessment Task

          #{focused_task_header(group_name, dimensions)}

          #{assessment_instruction(group_name, dimensions)} For interpretive dimensions, explicitly distinguish the assigned
          score from adjacent anchors in the schema fields. Use path sensitivity only for authored material variation.
          If published evidence genuinely cannot support a permitted value, use the AFAO-defined insufficient/uncertain
          state instead of guessing. Evidence pointers must cite page markers, section headings, encounter names, tables,
          or other locators actually present in the supplied source.

          #{interpretive_confidence_guidance_block(dimensions)}
        PROMPT
      )
    end

    private

    def build_nos_prompt(adventure:, source_extraction:, rubric:)
      Prompt.new(
        instructions: NOS_SYSTEM_INSTRUCTIONS,
        input: <<~PROMPT
          # Canonical Target

          Adventure ID: #{adventure.id}
          Adventure Title: #{adventure.title}
          Source Book: #{adventure.source_book}
          Book Publisher: #{adventure.publisher}
          Canonical Start Page: #{adventure.start_page}
          Canonical End Page: #{adventure.end_page}
          Source Scope Supplied: #{source_extraction.scope}
          Source File: #{source_extraction.source_file}

          The source body below is the evidence basis for the canonical target. Page markers are evidence locators.
          Material outside the canonical Adventure ID must not be allowed to contaminate the assessment.

          # Published Source Material

          #{source_extraction.text}

          # Frozen AFAO #{@afao.version} # of Sessions Rubric

          #{rubric}

          # Blind Assessment Task

          Independently assess # of Sessions for this canonical adventure using only the
          published source material and frozen rubric supplied above.

          Do not assess or infer scores for other AdventureFinder dimensions. Do not use
          prior AdventureFinder scores, benchmark placements, calibration results, model
          results, expected values, endpoint roles, or prior discussion of this adventure.

          Return the best-supported # of Sessions assessment required by the response schema.
          Evidence pointers must cite page markers, section headings, encounter names, tables,
          or other locators actually present in the supplied source.
        PROMPT
      )
    end

    def build_qualified_ee_prompt(adventure:, source_extraction:, rubric:)
      # Keep the qualified v0.5 system instructions exact. Shared response-field
      # guidance lives in the user input; changing it changes EE request provenance
      # and requires requalification before accepting new production results.
      Prompt.new(
        instructions: EE_QUALIFIED_SYSTEM_INSTRUCTIONS_V0_5,
        input: <<~PROMPT
          # Canonical Target

          Adventure ID: #{adventure.id}
          Adventure Title: #{adventure.title}
          Source Book: #{adventure.source_book}
          Book Publisher: #{adventure.publisher}
          Canonical Start Page: #{adventure.start_page}
          Canonical End Page: #{adventure.end_page}
          Source Scope Supplied: #{source_extraction.scope}
          Source File: #{source_extraction.source_file}

          The source body below is the evidence basis for the canonical target. Page markers are evidence locators.
          Material outside the canonical Adventure ID must not be allowed to contaminate the assessment.

          # Published Source Material

          #{source_extraction.text}

          # Frozen AFAO #{@afao.version} Exploration Emphasis Rubric

          #{rubric}

          # Blind Assessment Task

          Independently assess Exploration Emphasis for this canonical adventure using only
          the published source material and frozen rubric supplied above.

          Do not assess or infer scores for other AdventureFinder dimensions. Do not use prior
          AdventureFinder scores, benchmark placements, calibration results, model results,
          expected values, endpoint roles, or prior discussion of this adventure.

          Return the best-supported Exploration Emphasis assessment required by the response schema.
          For a scored assessment, perform adjacent-anchor falsification in the response schema.
          Populate adjacent_lower_reason when the assigned score is above 1 and
          adjacent_higher_reason when the assigned score is below 5. Use null only where
          the assigned score has no lower or higher adjacent anchor, respectively.

          #{INTERPRETIVE_CONFIDENCE_GUIDANCE}

          Evidence pointers must cite page markers, section headings, encounter names, tables,
          or other locators actually present in the supplied source.
        PROMPT
      )
    end

    def build_blind_gmbs_prompt(adventure:, source_extraction:, rubric:)
      Prompt.new(
        instructions: GMBS_SYSTEM_INSTRUCTIONS,
        input: <<~PROMPT
          # Canonical Target

          Adventure ID: #{adventure.id}
          Adventure Title: #{adventure.title}
          Source Book: #{adventure.source_book}
          Book Publisher: #{adventure.publisher}
          Canonical Start Page: #{adventure.start_page}
          Canonical End Page: #{adventure.end_page}
          Source Scope Supplied: #{source_extraction.scope}
          Source File: #{source_extraction.source_file}

          The source body below is the evidence basis for the canonical target. Page markers are evidence locators.
          Material outside the canonical Adventure ID must not be allowed to contaminate the assessment.

          # Published Source Material

          #{source_extraction.text}

          # Frozen AFAO #{@afao.version} GM Beginner Suitability Rubric

          #{rubric}

          # Blind Assessment Task

          Independently assess GM Beginner Suitability for this canonical adventure using only
          the published source material and frozen rubric supplied above.

          Do not assess or infer scores for other AdventureFinder dimensions. Do not use prior
          AdventureFinder scores, benchmark placements, calibration results, model results,
          expected values, endpoint roles, or prior discussion of this adventure.

          Return the best-supported GM Beginner Suitability assessment required by the response schema.
          For a scored assessment, perform adjacent-anchor falsification in the response schema.
          Populate adjacent_lower_reason when the assigned score is above 1 and
          adjacent_higher_reason when the assigned score is below 5. Use null only where
          the assigned score has no lower or higher adjacent anchor, respectively.

          #{INTERPRETIVE_CONFIDENCE_GUIDANCE}

          Evidence pointers must cite page markers, section headings, encounter names, tables,
          or other locators actually present in the supplied source.
        PROMPT
      )
    end

    def focused_task_header(group_name, dimensions)
      if dimensions == DimensionGroups.fetch(group_name)
        <<~TEXT.strip
          Scoring group: #{group_name}
          Required dimensions/values: #{dimensions.join('; ')}
        TEXT
      else
        <<~TEXT.strip
          Scoring dimension: #{dimensions.join('; ')}
          Required dimensions/values: #{dimensions.join('; ')}

          Assess only the required dimension/value in this focused pass. Do not assess or infer scores for other AdventureFinder dimensions.
        TEXT
      end
    end

    def assessment_instruction(group_name, dimensions)
      return "Assess every required value in this group." if dimensions == DimensionGroups.fetch(group_name)

      "Assess every required value in this focused pass."
    end

    def interpretive_confidence_guidance_block(dimensions)
      return "" if (dimensions & DimensionGroups::INTERPRETIVE).empty?

      INTERPRETIVE_CONFIDENCE_GUIDANCE
    end

    def levels_context_block(dimensions, levels_context)
      return "" unless dimensions.include?("Levels")

      context = levels_context.to_s.strip
      return "" if context.empty?

      <<~TEXT

        # Supplemental Pre-Canonical Levels Context

        The material below occurs before the canonical Start Page. Use it only as
        permitted by the Levels nested-adventure guardrail: to establish inherited
        entry state or directly governing level progression. It does not expand the
        canonical Adventure ID and must not be used to score # of Sessions.

        #{context}
      TEXT
    end

    def levels_guardrail_block(dimensions)
      return "" unless dimensions.include?("Levels")

      "\n\n#{LEVELS_NESTED_CONTEXT_GUARDRAIL_V0_1}"
    end

    def combat_guardrail_block(dimensions)
      return "" unless dimensions.include?("Combat Emphasis")

      "\n\n#{COMBAT_GUARDRAIL_V0_7_1}"
    end

    def investigation_emphasis_guardrail_block(dimensions)
      return "" unless dimensions.include?("Investigation Emphasis")

      "\n\n#{INVESTIGATION_EMPHASIS_GUARDRAIL_V0_3}"
    end

    def puzzle_problem_solving_emphasis_guardrail_block(dimensions)
      return "" unless dimensions.include?("Puzzle / Problem-Solving Emphasis")

      "\n\n#{PUZZLE_PROBLEM_SOLVING_EMPHASIS_GUARDRAIL_V0_1}"
    end

    def social_interaction_emphasis_guardrail_block(dimensions)
      return "" unless dimensions.include?("Social Interaction Emphasis")

      "\n\n#{SOCIAL_INTERACTION_EMPHASIS_GUARDRAIL_V0_2}"
    end

    def fantastic_weirdness_guardrail_block(dimensions)
      return "" unless dimensions.include?("Fantastic Weirdness")

      "\n\n#{FANTASTIC_WEIRDNESS_GUARDRAIL_V0_2}"
    end

    # Reset-era Seriousness qualification intentionally uses only the frozen
    # AFAO Seriousness rubric plus the ordinary production assessment shell.
    # Historical v0.1/v0.2 guardrail constants remain intact for comparison.
    def seriousness_guardrail_block(_dimensions)
      ""
    end

    def darkness_horror_intensity_guardrail_block(dimensions)
      return "" unless dimensions.include?("Darkness / Horror Intensity")

      "\n\n#{DARKNESS_HORROR_INTENSITY_GUARDRAIL_V0_1}"
    end

    def structural_openness_guardrail_block(dimensions)
      return "" unless dimensions.include?("Structural Openness")

      "\n\n#{STRUCTURAL_OPENNESS_GUARDRAIL_V0_2}"
    end

    def consequential_player_agency_guardrail_block(dimensions)
      return "" unless dimensions.include?("Consequential Player Agency")

      "\n\n#{CONSEQUENTIAL_PLAYER_AGENCY_GUARDRAIL_V0_3}"
    end

    def lethality_failure_severity_guardrail_block(dimensions)
      return "" unless dimensions.include?("Lethality / Failure Severity")

      "\n\n#{LETHALITY_FAILURE_SEVERITY_GUARDRAIL_V0_1}"
    end

    def rules_system_mastery_demand_guardrail_block(dimensions)
      return "" unless dimensions.include?("Rules / System-Mastery Demand")

      "\n\n#{RULES_SYSTEM_MASTERY_DEMAND_GUARDRAIL_V0_9}"
    end

    def gm_preparation_burden_guardrail_block(dimensions)
      return "" unless dimensions.include?("GM Preparation Burden")

      "\n\n#{GM_PREPARATION_BURDEN_GUARDRAIL_V0_6}"
    end

    def gm_improvisation_demand_guardrail_block(dimensions)
      return "" unless dimensions.include?("GM Improvisation Demand")

      "\n\n#{GM_IMPROVISATION_DEMAND_GUARDRAIL_V0_1}"
    end

    def player_beginner_suitability_guardrail_block(dimensions)
      return "" unless dimensions.include?("Player Beginner Suitability")

      "\n\n#{PLAYER_BEGINNER_SUITABILITY_GUARDRAIL_V0_2}"
    end

    def gm_beginner_suitability_guardrail_block(dimensions)
      return "" unless dimensions.include?("GM Beginner Suitability")

      "\n\n#{GM_BEGINNER_SUITABILITY_GUARDRAIL_V0_5}"
    end
  end
end
