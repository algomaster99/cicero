#
# Grammar for templates with embedded variables
#
# This grammar is used to parse a template and to generate a grammar that
# can parse instances of the template, automatically data binding to a template model.
#
# The grammar generation pipeline operates at 3 distinct levels: meta-meta (template definition language),
# meta (a template), an instance (a clause, a valid instance of a template).
#
# 1. Load this grammar
# 2. Parse the Template Grammar file (tgm) using this grammar, outputs AST1
# 3. Convert AST1 to a Nearley grammar (adding grammar rules from template model) 
#    that can parse instances of the template, outputs AST2
# 4. Parse instance of a template (a clause) using AST2, outputs the TemplateModel instance of the clause
# 5. Execute clause
#
@builtin "whitespace.ne"
@builtin "string.ne"

@{%
  const flatten = d => {
    return d.reduce(
      (a, b) => {
          if(b) {
            return a.concat(b);
          } else {
              return a;
          }
      },
      []
    );
  };

const moo = require("moo");

const escapeNearley = (x) => {
    return x.replace(/\t/g, '\\t') // Replace tab due to Nearley bug #nearley/issues/413
        .replace(/\f/g, '\\f')
        .replace(/\r/g, '\\r');
}

// we use lexer states to distinguish between the tokens
// in the text and the tokens inside the variables
const lexer = moo.states({
    main: {
        // a chunk is everything up until '{[', even across newlines. We then trim off the '{['
        // we also push the lexer into the 'var' state
        Chunk: {
            match: /[^]*?{{/,
            lineBreaks: true,
            push: 'markup',
            value: x => escapeNearley(x.slice(0, -2))
        },
        // we now need to consume everything up until the end of the buffer.
        // note that the order of these two rules is important!
        LastChunk : {
            match: /[^]+/,
            lineBreaks: true,
            value: x => escapeNearley(x)
        }
    },
    markup: { // This is a dispatch to the correct lexical state (using moo's "next")
        markupstartblock: {
            match: '#',
            next: 'startblock',
        },
        markupstartref: {
            match: '>',
            next: 'startref',
        },
        markupendblock: {
            match: '/',
            next: 'endblock',
        },
        markupexpr: {
            match: '%',
            next: 'expr',
        },
        varend: {
            match: '}}',
            pop: true
        }, // pop back to main state
        varelseid: 'else',
        varid: {
          match: /[a-zA-Z_][_a-zA-Z0-9]*/,
          type: moo.keywords({varas: 'as'})
        },
        varstring: /".*?"/,
        varspace: ' ',
    },
    expr: {
        exprend: {
            match: /[^]*?[%]}}/,
            lineBreaks: true,
            pop: true
        },
    },
    startblock: {
        startblockend: {
            match: '}}',
            pop: true,
        }, // pop back to main state
        startblockspace: / +/,
        startclauseid: 'clause',
        startwithid: 'with',
        startulistid: 'ulist',
        startolistid: 'olist',
        startjoinid: 'join',
        startifid: 'if',
        startblockstring: /".*?"/,
        startblockid: /[a-zA-Z_][_a-zA-Z0-9]*/,
    },
    startref: {
        startrefend: {
            match: '}}',
            pop: true,
        }, // pop back to main state
        startrefspace: / +/,
        startrefid: /[a-zA-Z_][_a-zA-Z0-9]*/,
    },
    endblock: {
        endblockend: {
            match: '}}',
            pop: true
        }, // pop back to main state
        endclauseid: 'clause',
        endwithid: 'with',
        endulistid: 'ulist',
        endolistid: 'olist',
        endjoinid: 'join',
        endifid: 'if',
    },
});
%}

@lexer lexer

TEMPLATE -> 
    # Only allow contract templates for now until we get to milestone 2
    #  CLAUSE_TEMPLATE {% id %}
    #|
    CONTRACT_TEMPLATE {% id %}

CONTRACT_TEMPLATE -> CONTRACT_ITEM:* %LastChunk:?
{% (data) => {
        return {
            type: 'ContractTemplate',
            data: flatten(data)
        };
    }
%}

CONTRACT_ITEM -> 
      %Chunk {% id %}
    | %markupstartblock ULIST_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock OLIST_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock JOIN_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock IF_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock CLAUSE_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock WITH_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartref CLAUSE_BLOCK_EXTERNAL {% (data) => { return data[1]; } %}
    | %markupexpr CLAUSE_EXPR {% (data) => { return data[1]; } %}
    | VARIABLE {% id %}

CLAUSE_TEMPLATE -> CLAUSE_ITEM:* %LastChunk:?
{% (data) => {
        return {
            type: 'ClauseTemplate',
            data: flatten(data)
        };
    }
%}

CLAUSE_ITEM -> 
      %Chunk {% id %} 
    | %markupstartblock ULIST_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock OLIST_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock JOIN_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock IF_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupstartblock WITH_BLOCK_INLINE {% (data) => { return data[1]; } %}
    | %markupexpr CLAUSE_EXPR {% (data) => { return data[1]; } %}
    | VARIABLE {% id %}

# An expression
CLAUSE_EXPR -> %exprend
{% (data) => {
        return {
            type: 'Expr'
        }
    }
%}

CLAUSE_BLOCK_INLINE -> %startclauseid %startblockspace %startblockid %startblockend CLAUSE_TEMPLATE %markupendblock %endclauseid %endblockend
{% (data,l,reject) => {
    // Check that opening and closing clause tags match
    // Note: this line makes the parser non-context-free
    return {
        type: 'ClauseBinding',
        template: data[4],
        fieldName: data[2]
    }
}
%}

WITH_BLOCK_INLINE -> %startwithid %startblockspace %startblockid %startblockend CLAUSE_TEMPLATE %markupendblock %endwithid %endblockend
{% (data,l,reject) => {
    // Check that opening and closing clause tags match
    // Note: this line makes the parser non-context-free
    return {
        type: 'WithBinding',
        template: data[4],
        fieldName: data[2]
    }
}
%}

# Binds the variable to a Clause in the template model. The type of the clause
# in the grammar is inferred from the type of the model element
CLAUSE_BLOCK_EXTERNAL -> %startrefspace:? %startrefid %startrefend
{% (data) => {
    return {
        type: 'ClauseExternalBinding',
        fieldName: data[1]
    }
} 
%}

ULIST_BLOCK_INLINE -> %startulistid %startblockspace %startblockid %startblockend CLAUSE_TEMPLATE %markupendblock %endulistid %endblockend
{% (data,l,reject) => {
    // Check that opening and closing clause tags match
    // Note: this line makes the parser non-context-free
        return {
            type: 'UListBinding',
            template: data[4],
            fieldName: data[2]
        }
}
%}

OLIST_BLOCK_INLINE -> %startolistid %startblockspace %startblockid %startblockend CLAUSE_TEMPLATE %markupendblock %endolistid %endblockend
{% (data,l,reject) => {
    // Check that opening and closing clause tags match
    // Note: this line makes the parser non-context-free
        return {
            type: 'OListBinding',
            template: data[4],
            fieldName: data[2]
        }
}
%}

JOIN_BLOCK_INLINE -> %startjoinid %startblockspace %startblockid %startblockspace %startblockstring %startblockend CLAUSE_TEMPLATE %markupendblock %endjoinid %endblockend
{% (data,l,reject) => {
    // Check that opening and closing clause tags match
    // Note: this line makes the parser non-context-free
        return {
            type: 'JoinBinding',
            template: data[6],
            separator: JSON.parse(data[4].value),
            fieldName: data[2]
        }
}
%}

IF_BLOCK_INLINE ->
      %startifid %startblockspace %startblockid %startblockend %Chunk %markupendblock %endifid %endblockend
{% (data,l,reject) => {
    // Check that opening and closing clause tags match
    // Note: this line makes the parser non-context-free
        return {
            type: 'IfBinding',
            stringIf: data[4],
            fieldName: data[2]
        }
}
%}
    | %startifid %startblockspace %startblockid %startblockend %Chunk %varelseid %varend %Chunk %markupendblock %endifid %endblockend
{% (data,l,reject) => {
    // Check that opening and closing clause tags match
    // Note: this line makes the parser non-context-free
        return {
            type: 'IfElseBinding',
            stringIf: data[4],
            stringElse: data[7],
            fieldName: data[2]
        }
}
%}

# A variable may be one of the sub-types below
VARIABLE -> 
      FORMATTED_BINDING {% id %}
    | BINDING {% id %} 

# A Formatted binding specifies how a field is parsed inline. For example, for a DateTime field:
# {[fieldName as "YYYY-MM-DD HH:mm Z"]}
FORMATTED_BINDING -> %varid %varspace %varas %varspace %varstring %varend
{% (data) => {
        return {
            type: 'FormattedBinding',
            fieldName: data[0],
            format: data[4],
        };
    }
%}

# Binds the variable to a field in the template model. The type of the variable
# in the grammar is inferred from the type of the model element
# {[fieldName]}
BINDING -> %varid %varend
{% (data) => {
        return {
            type: 'Binding',
            fieldName: data[0]
        };
    }
%}
