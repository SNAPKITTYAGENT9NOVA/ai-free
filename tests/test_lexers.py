"""Unit tests for lexical analyzers (BCPL, Forth, Wolfram)."""

import pytest
from src.frontends.bcpl import BCPLLexer, TokenType as BCPLTokenType
from src.frontends.forth import ForthLexer, TokenType as ForthTokenType
from src.frontends.wolfram import WolframLexer, TokenType as WolframTokenType


class TestBCPLLexer:
    """Tests for BCPL lexer."""

    def test_keywords(self):
        lexer = BCPLLexer("let if while for")
        tokens = lexer.tokenize()
        assert tokens[0].type == BCPLTokenType.LET
        assert tokens[1].type == BCPLTokenType.IF
        assert tokens[2].type == BCPLTokenType.WHILE
        assert tokens[3].type == BCPLTokenType.FOR

    def test_identifiers_and_numbers(self):
        lexer = BCPLLexer("x 42 myVar 3.14")
        tokens = lexer.tokenize()
        assert tokens[0].type == BCPLTokenType.IDENTIFIER
        assert tokens[0].value == "x"
        assert tokens[1].type == BCPLTokenType.NUMBER
        assert tokens[1].value == "42"
        assert tokens[2].type == BCPLTokenType.IDENTIFIER
        assert tokens[3].type == BCPLTokenType.NUMBER
        assert tokens[3].value == "3.14"

    def test_operators(self):
        lexer = BCPLLexer("+ - * / << >> & | ^ ~")
        tokens = lexer.tokenize()
        assert tokens[0].type == BCPLTokenType.PLUS
        assert tokens[1].type == BCPLTokenType.MINUS
        assert tokens[2].type == BCPLTokenType.STAR
        assert tokens[3].type == BCPLTokenType.SLASH
        assert tokens[4].type == BCPLTokenType.LSHIFT
        assert tokens[5].type == BCPLTokenType.RSHIFT

    def test_delimiters(self):
        lexer = BCPLLexer("( ) [ ] { } ; , .")
        tokens = lexer.tokenize()
        assert tokens[0].type == BCPLTokenType.LPAREN
        assert tokens[1].type == BCPLTokenType.RPAREN
        assert tokens[2].type == BCPLTokenType.LBRACKET

    def test_string_and_char(self):
        lexer = BCPLLexer('"hello" \'x\'')
        tokens = lexer.tokenize()
        assert tokens[0].type == BCPLTokenType.STRING
        assert tokens[0].value == "hello"
        assert tokens[1].type == BCPLTokenType.CHAR
        assert tokens[1].value == "x"

    def test_comments(self):
        lexer = BCPLLexer("x // comment\ny")
        tokens = lexer.tokenize()
        assert tokens[0].type == BCPLTokenType.IDENTIFIER
        assert tokens[0].value == "x"
        assert tokens[1].type == BCPLTokenType.IDENTIFIER
        assert tokens[1].value == "y"

    def test_comparison_operators(self):
        lexer = BCPLLexer("== != < > <= >=")
        tokens = lexer.tokenize()
        assert tokens[0].type == BCPLTokenType.EQ
        assert tokens[1].type == BCPLTokenType.NE


class TestForthLexer:
    """Tests for Forth lexer."""

    def test_builtin_words(self):
        lexer = ForthLexer("dup drop swap + - * /")
        tokens = lexer.tokenize()
        assert tokens[0].type == ForthTokenType.DUP
        assert tokens[1].type == ForthTokenType.DROP
        assert tokens[2].type == ForthTokenType.SWAP
        assert tokens[3].type == ForthTokenType.ADD

    def test_custom_words(self):
        lexer = ForthLexer("myword x y")
        tokens = lexer.tokenize()
        assert tokens[0].type == ForthTokenType.WORD
        assert tokens[0].value == "myword"
        assert tokens[1].type == ForthTokenType.WORD

    def test_numbers(self):
        lexer = ForthLexer("42 0xFF -3")
        tokens = lexer.tokenize()
        assert tokens[0].type == ForthTokenType.NUMBER
        assert tokens[0].value == "42"
        assert tokens[1].type == ForthTokenType.NUMBER
        assert tokens[1].value == "0xFF"
        assert tokens[2].type == ForthTokenType.NUMBER
        assert tokens[2].value == "-3"

    def test_string_literals(self):
        lexer = ForthLexer('"hello world"')
        tokens = lexer.tokenize()
        assert tokens[0].type == ForthTokenType.STRING
        assert tokens[0].value == "hello world"

    def test_colon_definition(self):
        lexer = ForthLexer(": square dup * ;")
        tokens = lexer.tokenize()
        assert tokens[0].type == ForthTokenType.COLON
        assert tokens[1].type == ForthTokenType.WORD
        assert tokens[1].value == "square"
        assert tokens[2].type == ForthTokenType.DUP

    def test_comments(self):
        lexer = ForthLexer("x \\ comment\ny")
        tokens = lexer.tokenize()
        assert tokens[0].type == ForthTokenType.WORD
        assert tokens[1].type == ForthTokenType.WORD


class TestWolframLexer:
    """Tests for Wolfram lexer."""

    def test_symbols_and_functions(self):
        lexer = WolframLexer("x Plus Times Sin")
        tokens = lexer.tokenize()
        assert tokens[0].type == WolframTokenType.SYMBOL
        assert tokens[0].value == "x"
        assert tokens[1].type == WolframTokenType.FUNCTION
        assert tokens[1].value == "Plus"

    def test_numbers(self):
        lexer = WolframLexer("42 3.14 1.5e-3")
        tokens = lexer.tokenize()
        assert tokens[0].type == WolframTokenType.NUMBER
        assert tokens[0].value == "42"
        assert tokens[1].type == WolframTokenType.NUMBER
        assert tokens[1].value == "3.14"
        assert tokens[2].type == WolframTokenType.NUMBER

    def test_operators(self):
        lexer = WolframLexer("+ - * / ^")
        tokens = lexer.tokenize()
        assert tokens[0].type == WolframTokenType.PLUS
        assert tokens[1].type == WolframTokenType.MINUS
        assert tokens[2].type == WolframTokenType.STAR

    def test_delimiters(self):
        lexer = WolframLexer("[ ] { } ( ) , ;")
        tokens = lexer.tokenize()
        assert tokens[0].type == WolframTokenType.LBRACKET
        assert tokens[1].type == WolframTokenType.RBRACKET

    def test_string_literals(self):
        lexer = WolframLexer('"hello"')
        tokens = lexer.tokenize()
        assert tokens[0].type == WolframTokenType.STRING
        assert tokens[0].value == "hello"

    def test_comments(self):
        lexer = WolframLexer("x (* comment *) y")
        tokens = lexer.tokenize()
        assert tokens[0].type == WolframTokenType.SYMBOL
        assert tokens[0].value == "x"
        assert tokens[1].type == WolframTokenType.SYMBOL
        assert tokens[1].value == "y"
