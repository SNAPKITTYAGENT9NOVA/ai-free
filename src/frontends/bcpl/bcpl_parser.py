"""BCPL parser: tokens → AST."""

from typing import List, Optional
from .bcpl_lexer import Token, TokenType, BCPLLexer
from .bcpl_ast import (
    Expr, BinOp, UnaryOp, Number, Identifier, Call, Load, Alloc,
    Stmt, Assignment, Store, IfStmt, WhileStmt, ForStmt, ReturnStmt, ExprStmt, Block,
    FuncDef, Program
)


class ParseError(Exception):
    """Parser error."""
    pass


class BCPLParser:
    """BCPL parser: converts token stream to AST."""

    def __init__(self, tokens: List[Token]):
        self.tokens = tokens
        self.pos = 0

    def current(self) -> Optional[Token]:
        if self.pos >= len(self.tokens):
            return None
        return self.tokens[self.pos]

    def peek(self, offset: int = 1) -> Optional[Token]:
        pos = self.pos + offset
        if pos >= len(self.tokens):
            return None
        return self.tokens[pos]

    def advance(self):
        self.pos += 1

    def expect(self, token_type: TokenType) -> Token:
        token = self.current()
        if not token or token.type != token_type:
            raise ParseError(f"Expected {token_type}, got {token}")
        self.advance()
        return token

    def match(self, *token_types: TokenType) -> bool:
        token = self.current()
        return token and token.type in token_types

    def parse_program(self) -> Program:
        """Parse BCPL program: series of function definitions."""
        functions = []
        while self.current() and self.current().type != TokenType.EOF:
            if self.current().type == TokenType.ROUTINE:
                functions.append(self.parse_function())
            else:
                self.advance()
        return Program(functions=functions)

    def parse_function(self) -> FuncDef:
        """Parse function definition: routine name(params) { body }"""
        self.expect(TokenType.ROUTINE)
        name = self.expect(TokenType.IDENTIFIER).value
        self.expect(TokenType.LPAREN)
        params = []
        while not self.match(TokenType.RPAREN):
            params.append(self.expect(TokenType.IDENTIFIER).value)
            if self.match(TokenType.COMMA):
                self.advance()
        self.expect(TokenType.RPAREN)
        self.expect(TokenType.LBRACE)
        body = self.parse_block_body()
        self.expect(TokenType.RBRACE)
        return FuncDef(name=name, params=params, body=body)

    def parse_block_body(self) -> List[Stmt]:
        """Parse statements inside a block."""
        stmts = []
        while not self.match(TokenType.RBRACE, TokenType.EOF):
            stmts.append(self.parse_statement())
        return stmts

    def parse_statement(self) -> Stmt:
        """Parse a single statement."""
        if self.match(TokenType.IF):
            return self.parse_if_stmt()
        elif self.match(TokenType.WHILE):
            return self.parse_while_stmt()
        elif self.match(TokenType.FOR):
            return self.parse_for_stmt()
        elif self.match(TokenType.RETURN):
            return self.parse_return_stmt()
        elif self.match(TokenType.LBRACE):
            return self.parse_block()
        else:
            return self.parse_expr_stmt()

    def parse_if_stmt(self) -> IfStmt:
        """Parse if statement: if(cond) then block else block"""
        self.expect(TokenType.IF)
        self.expect(TokenType.LPAREN)
        condition = self.parse_expression()
        self.expect(TokenType.RPAREN)
        self.expect(TokenType.LBRACE)
        then_block = self.parse_block_body()
        self.expect(TokenType.RBRACE)
        else_block = None
        if self.match(TokenType.ELSE):
            self.advance()
            self.expect(TokenType.LBRACE)
            else_block = self.parse_block_body()
            self.expect(TokenType.RBRACE)
        return IfStmt(condition=condition, then_block=then_block, else_block=else_block)

    def parse_while_stmt(self) -> WhileStmt:
        """Parse while loop: while(cond) do block"""
        self.expect(TokenType.WHILE)
        self.expect(TokenType.LPAREN)
        condition = self.parse_expression()
        self.expect(TokenType.RPAREN)
        self.expect(TokenType.LBRACE)
        body = self.parse_block_body()
        self.expect(TokenType.RBRACE)
        return WhileStmt(condition=condition, body=body)

    def parse_for_stmt(self) -> ForStmt:
        """Parse for loop: for(init; cond; update) do block"""
        self.expect(TokenType.FOR)
        self.expect(TokenType.LPAREN)
        init = None
        if not self.match(TokenType.SEMICOLON):
            init = self.parse_expr_stmt()
        else:
            self.advance()
        condition = self.parse_expression()
        self.expect(TokenType.SEMICOLON)
        update = None
        if not self.match(TokenType.RPAREN):
            update = self.parse_expr_stmt()
        self.expect(TokenType.RPAREN)
        self.expect(TokenType.LBRACE)
        body = self.parse_block_body()
        self.expect(TokenType.RBRACE)
        return ForStmt(init=init, condition=condition, update=update, body=body)

    def parse_return_stmt(self) -> ReturnStmt:
        """Parse return statement: return expr;"""
        self.expect(TokenType.RETURN)
        value = None
        if not self.match(TokenType.SEMICOLON):
            value = self.parse_expression()
        self.expect(TokenType.SEMICOLON)
        return ReturnStmt(value=value)

    def parse_block(self) -> Block:
        """Parse block: { stmts }"""
        self.expect(TokenType.LBRACE)
        stmts = self.parse_block_body()
        self.expect(TokenType.RBRACE)
        return Block(stmts=stmts)

    def parse_expr_stmt(self) -> Stmt:
        """Parse expression or assignment statement: expr; or lhs = rhs;"""
        expr = self.parse_expression()
        if self.match(TokenType.ASSIGN):
            if isinstance(expr, Identifier):
                self.advance()
                rhs = self.parse_expression()
                self.expect(TokenType.SEMICOLON)
                return Assignment(lhs=expr.name, rhs=rhs)
            elif isinstance(expr, Load):
                self.advance()
                rhs = self.parse_expression()
                self.expect(TokenType.SEMICOLON)
                return Store(address=expr.address, value=rhs)
        self.expect(TokenType.SEMICOLON)
        return ExprStmt(expr=expr)

    def parse_expression(self) -> Expr:
        """Parse expression (left-associative)."""
        return self.parse_assignment()

    def parse_assignment(self) -> Expr:
        """Parse assignment: lhs = rhs (kept as expr for now, converted to stmt later)"""
        expr = self.parse_or_expr()
        return expr

    def parse_or_expr(self) -> Expr:
        """Parse logical OR: expr | expr"""
        left = self.parse_and_expr()
        while self.match(TokenType.BITOR):
            self.advance()
            right = self.parse_and_expr()
            left = BinOp(op="|", left=left, right=right)
        return left

    def parse_and_expr(self) -> Expr:
        """Parse logical AND: expr & expr"""
        left = self.parse_cmp_expr()
        while self.match(TokenType.BITAND):
            self.advance()
            right = self.parse_cmp_expr()
            left = BinOp(op="&", left=left, right=right)
        return left

    def parse_cmp_expr(self) -> Expr:
        """Parse comparison: expr == expr, expr < expr, etc."""
        left = self.parse_add_expr()
        while self.match(TokenType.EQ, TokenType.NE, TokenType.LT, TokenType.LE, TokenType.GT, TokenType.GE):
            op = self.current().value
            self.advance()
            right = self.parse_add_expr()
            left = BinOp(op=op, left=left, right=right)
        return left

    def parse_add_expr(self) -> Expr:
        """Parse addition/subtraction: expr + expr"""
        left = self.parse_mul_expr()
        while self.match(TokenType.PLUS, TokenType.MINUS):
            op = self.current().value
            self.advance()
            right = self.parse_mul_expr()
            left = BinOp(op=op, left=left, right=right)
        return left

    def parse_mul_expr(self) -> Expr:
        """Parse multiplication/division: expr * expr"""
        left = self.parse_unary_expr()
        while self.match(TokenType.STAR, TokenType.SLASH, TokenType.MOD):
            op = self.current().value
            self.advance()
            right = self.parse_unary_expr()
            left = BinOp(op=op, left=left, right=right)
        return left

    def parse_unary_expr(self) -> Expr:
        """Parse unary operations: -expr, !expr, @address"""
        if self.match(TokenType.MINUS):
            self.advance()
            operand = self.parse_unary_expr()
            return UnaryOp(op="-", operand=operand)
        elif self.match(TokenType.BITAND):
            self.advance()
            operand = self.parse_unary_expr()
            return Load(address=operand)
        return self.parse_postfix_expr()

    def parse_postfix_expr(self) -> Expr:
        """Parse postfix operations: function calls, indexing."""
        expr = self.parse_primary()
        while True:
            if self.match(TokenType.LPAREN):
                self.advance()
                args = []
                while not self.match(TokenType.RPAREN):
                    args.append(self.parse_expression())
                    if self.match(TokenType.COMMA):
                        self.advance()
                self.expect(TokenType.RPAREN)
                if isinstance(expr, Identifier):
                    expr = Call(name=expr.name, args=args)
            else:
                break
        return expr

    def parse_primary(self) -> Expr:
        """Parse primary expressions: literals, identifiers, parenthesized expressions."""
        if self.match(TokenType.NUMBER):
            value = int(self.current().value)
            self.advance()
            return Number(value=value)
        elif self.match(TokenType.IDENTIFIER):
            name = self.current().value
            self.advance()
            return Identifier(name=name)
        elif self.match(TokenType.LPAREN):
            self.advance()
            expr = self.parse_expression()
            self.expect(TokenType.RPAREN)
            return expr
        else:
            raise ParseError(f"Unexpected token: {self.current()}")


def parse_bcpl(source: str) -> Program:
    """Parse BCPL source code → AST."""
    lexer = BCPLLexer(source)
    tokens = lexer.tokenize()
    parser = BCPLParser(tokens)
    return parser.parse_program()
