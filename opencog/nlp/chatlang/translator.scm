;; ChatLang DSL for chat authoring rules
;;
;; A partial implementation of the top level translator that produces
;; PSI rules.
(use-modules (opencog)
             (opencog nlp)
             (opencog exec)
             (opencog openpsi)
             (opencog eva-behavior)
             (srfi srfi-1))

;; Shared variables for all terms
(define atomese-variable-template (list (TypedVariable (Variable "$S")
                                                       (Type "SentenceNode"))
                                        (TypedVariable (Variable "$P")
                                                       (Type "ParseNode"))))

;; Shared conditions for all terms
(define atomese-condition-template (list (Parse (Variable "$P")
                                                (Variable "$S"))
                                         (State (Anchor "Currently Processing")
                                                (Variable "$S"))))

(define (process-pattern-term term atomese-pattern)
  "Process a single term -- calls the term function and appends the new
   variables and conditions to the existing pair."
  (let* ((atomese-for-term (primitive-eval term))
         (vars (append (car atomese-pattern) (car atomese-for-term)))
         (conds (append (cdr atomese-pattern) (cdr atomese-for-term))))
    (cons vars conds)))

(define (term-sequence-check terms)
  "Checks terms occur in the desired order. To be implemented."
  ; A hacky way to quickly find the lemma of a word using WordNet
  (define (get-lemma word)
    (let* ((cmd-string (string-append "wn " word " | grep \"Information available for .\\+\""))
           (port (open-input-pipe cmd-string))
           (lemma ""))
      (do ((line (get-line port) (get-line port)))
          ((eof-object? line))
        (let ((l (car (last-pair (string-split line #\ )))))
          (if (not (equal? word l))
            (set! lemma l))))
      (close-pipe port)
      (if (string-null? lemma) word lemma)))

  (define word-list
    (map (lambda (w) (cond ((equal? 'concept (car w)) (Glob (car (cdr w))))
                           (else (Word (car (cdr w))))))
         terms))
  (Evaluation (GroundedPredicate "scm: check-word-sequence")
              (List (Variable "$S")
                    (List word-list))))

(define (get-word-lemma sent-node target-link-type)
  (List (append-map
    (lambda (w)
      ; Ignore LEFT-WALL and punctuations
      (if (or (string-prefix? "LEFT-WALL" (cog-name w))
              (word-inst-match-pos? w "punctuation"))
          '()
          (cog-chase-link target-link-type 'WordNode w)))
    (car (sent-get-words-in-order sent-node)))))

(define (get-sent-words sent-node)
  "Get the words associate with sent-node"
  (get-word-lemma sent-node 'ReferenceLink))

(define (get-sent-lemmas sent-node)
  "Get the lemma of the words associate with sent-node"
  (get-word-lemma sent-node 'LemmaLink))

(define (check-word-sequence sent-node word-list)
  "Check if the sequence of the words associate with the
   sentence 'sent-node' matches with word-list"
  (let* ((sent-word-list (get-sent-words sent-node))
         (sent-lemma-list (get-sent-lemmas sent-node))
         (exact-match (or (equal? word-list sent-word-list)
                          (equal? word-list sent-lemma-list)))
         (map-result-1 (cog-execute! (Map word-list (Set sent-word-list))))
         (map-result-2 (cog-execute! (Map word-list (Set sent-lemma-list))))
         (dual-match (or (not (null? (gar map-result-1)))
                         (not (null? (gar map-result-2))))))
  (if (or exact-match dual-match)
      (stv 1 1)
      (stv 0 1))))

(define (say text)
  "Say the text and clear the state"
  (And (True (Put (DefinedPredicate "Say") (Node text)))
       (True (Put (State (Anchor "Currently Processing") (Variable "$x"))
                  (Concept "Default State")))))

(define yakking (psi-demand "Yakking" 0.9))

(define* (chat-rule pattern action #:optional name)
  "Top level translation function. Pattern is a quoted list of terms,
   and action is a quoted list of actions or a single action."
  (let* ((template (cons atomese-variable-template atomese-condition-template))
         (proc-terms (fold process-pattern-term
                           template
                           pattern))
         ; There may be duplicates if the pattern contains any two or more
         ; of the main-* terms, e.g. main-verb, main-subj, and main-obj
         (var-list (delete-duplicates (car proc-terms)))
         (cond-list (delete-duplicates (cdr proc-terms)))
         (seq-check (term-sequence-check pattern)))
    (psi-rule
      (list (Satisfaction (VariableList var-list)
                          (And (append cond-list (list seq-check)))))
      (primitive-eval action)
      (True)
      (stv .9 .9)
      yakking
      name)))

(define (member-words w)
  (let ((words (string-split w #\sp)))
    (if (= 1 (length words))
        (Word (car words))
        (List (map-in-order Word words)))))

(define (chat-concept name members)
  "Lets users create named concepts with explicit membership lists."
  (let* ((c (Concept name))
         (ref-members (append-map (lambda (m) (list (Reference (member-words m) c)))
                                  members)))
    ref-members))
