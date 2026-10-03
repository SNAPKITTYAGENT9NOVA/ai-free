"""Forth Abstract Syntax Tree (AST) definitions.

Forth is stack-based. AST represents high-level stack operations.
"""

from dataclasses import dataclass
from typing import List, Optional


@dataclass
class Word:
    """Base Forth word."""
    name: str


@dataclass
class NumberWord(Word):
    """Numeric literal."""
    value: int


@dataclass
class BuiltinWord(Word):
    """Built-in Forth word (DUP, DROP, +, etc.)."""
    pass


@dataclass
class CustomWord(Word):
    """User-defined word reference."""
    pass


@dataclass
class StringWord(Word):
    """String literal."""
    value: str


@dataclass
class ControlFlow(Word):
    """Control flow: IF, THEN, ELSE, DO, LOOP."""
    pass


@dataclass
class WordDef:
    """Word definition: : name ... ;"""
    name: str
    body: List[Word]


@dataclass
class ForthProgram:
    """Forth program: list of word definitions."""
    words: List[Word]
    definitions: List[WordDef]
