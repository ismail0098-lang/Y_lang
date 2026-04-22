// ============================================================
//  Y-Lang  —  Linear Type Tracker
//  linear_tracker.rs
//
//  Tracks synchronization obligations in the AST. 
//  Whenever an async transfer (e.g. `cp_async`) creates a 
//  `Transfer` type, this tracker binds it to the scope.
//  It enforces exactly-once consumption by `pipe.wait`.
// ============================================================

#![allow(dead_code)]

use std::collections::{HashMap, HashSet};
use crate::ast::Span;

/// An obligation to synchronize memory before use.
#[derive(Debug, Clone)]
pub struct Obligation {
    pub name: String,
    pub created_at: Span,
    pub consumed: bool,
}

/// The LinearTracker manages lexical scopes and enforces 
/// linear typing rules on Transfer obligations.
#[derive(Debug, Default)]
pub struct LinearTracker {
    /// A stack of scopes, each containing variable to Obligation mappings.
    scopes: Vec<HashMap<String, Obligation>>,
    pub errors: Vec<String>,
}

impl LinearTracker {
    pub fn new() -> Self {
        Self {
            scopes: vec![HashMap::new()],
            errors: Vec::new(),
        }
    }

    pub fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    /// Pops the top scope. If any obligation was left unconsumed, returns an error.
    pub fn pop_scope(&mut self) {
        if let Some(scope) = self.scopes.pop() {
            for (name, ob) in scope {
                if !ob.consumed {
                    self.errors.push(format!(
                        "Line {}: Linear Type Error: `{}` is a Transfer obligation that was never consumed. \
                         You must call `pipe.wait({})` before it goes out of scope.",
                        ob.created_at.line, name, name
                    ));
                }
            }
        }
    }

    /// Register a new linear obligation in the current scope.
    pub fn register_obligation(&mut self, name: String, span: Span) {
        if let Some(scope) = self.scopes.last_mut() {
            // Shadowing an existing obligation unconsumed is also an error.
            if let Some(prev) = scope.get(&name) {
                if !prev.consumed {
                    self.errors.push(format!(
                        "Line {}: Linear Type Error: `{}` was reassigned before its previous obligation was consumed.",
                        span.line, name
                    ));
                }
            }
            scope.insert(name.clone(), Obligation {
                name,
                created_at: span,
                consumed: false,
            });
        }
    }

    /// Mark an obligation as consumed. Returns true if successful, false if it didn't exist or was already consumed.
    pub fn consume_obligation(&mut self, name: &str, use_span: Span) -> bool {
        for scope in self.scopes.iter_mut().rev() {
            if let Some(ob) = scope.get_mut(name) {
                if ob.consumed {
                    self.errors.push(format!(
                        "Line {}: Linear Type Error: `{}` transfer obligation was consumed twice. \
                        It was already awaited previously.",
                        use_span.line, name
                    ));
                    return false;
                } else {
                    ob.consumed = true;
                    return true;
                }
            }
        }
        
        // Not a tracked linear transfer (or it was never defined/is just a normal variable)
        // Handled by standard type checking elsewhere.
        true 
    }

    pub fn has_errors(&self) -> bool {
        !self.errors.is_empty()
    }
}
