"""BCPL Parser: tokens → AST.

BCPL (Basic Combined Programming Language) is a procedural language from the 1960s.
This parser handles:
  - Keywords: let, if, while, for, return, etc.
  - Operators: arithmetic, bitwise, comparison
  - Identifiers and literals
  - Control flow structures
  - Function definitions
"""

from typing import List, Optional
from src.frontends.bcpl.bcpl_lexer import Token, TokenType, BCPLLexer
from .base_parser import (
    Parser, ParseError, Program, FunctionDef, Stmt, Expr,
    ASTNode, Literal, Identifier, BinaryOp, UnaryOp, Call, Load,
    Block, ExprStmt, Assignment, Store, IfStmt, WhileStmt, ForStmt, ReturnStmt,
    SourceLocation
)


class BCPLParser(Parser[Program]):
    """BCPL parser: tokens → AST with source location tracking."""

    def parse(self) -> Program:
        """Parse BCPL program: sequence of function definitions."""
        items = []
        while self.current() and self.current().type != TokenType.EOF:
            if self.current().type == TokenType.ROUTINE:
                items.append(self.parse_function())
            else:
                # Skip unknown tokens
                self.advance()
        return Program(items=items).set_location(1, 0, "program")

    def parse_function(self) -> FunctionDef:
        """Parse function definition: routine name(params) { body }."""
        routine_token = self.expect(TokenType.ROUTINE)
        name_token = self.expect(TokenType.IDENTIFIER)
        name = name_token.value

        self.expect(TokenType.LPAREN)
        params = []
        while not self.match(TokenType.RPAREN):
            param_token = self.expect(TokenType.IDENTIFIER)
            params.append(param_token.value)
            if self.match(TokenType.COMMA):
                self.advance()
        self.expect(TokenType.RPAREN)

        self.expect(TokenType.LBRACE)
        body = self.parse_statements()
        self.expect(TokenType.RBRACE)

        func = FunctionDef(
            name=name,
            params=params,
            body=body
        )
        func.set_location(routine_token.line, routine_token.col, "routine")
        return func

    def parse_statements(self) -> List[Stmt]:
        """Parse list of statements until closing brace or EOF."""
        stmts = []
        while not self.match(TokenType.RBRACE, TokenType.EOF):
            stmt = self.parse_statement()
            if stmt:
                stmts.append(stmt)
        return stmts

    def parse_statement(self) -> Optional[Stmt]:
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
            # Try expression statement (assignment or plain expression)
            return self.parse_expr_stmt()

    def parse_if_stmt(self) -> IfStmt:
        """Parse if statement: if(cond) { block } else { block }."""
        if_token = self.expect(TokenType.IF)
        self.expect(TokenType.LPAREN)
        condition = self.parse_expression()
        self.expect(TokenType.RPAREN)
        self.expect(TokenType.LBRACE)
        consequent = self.parse_statements()
        self.expect(TokenType.RBRACE)

        alternate = None
        if self.match(TokenType.ELSE):
            self.advance()
            self.expect(TokenType.LBRACE)
            alternate = self.parse_statements()
            self.expect(TokenType.RBRACE)

        stmt = IfStmt(
            condition=condition,
            consequent=consequent,
            alternate=alternate
        )
        stmt.set_location(if_token.line, if_token.col, "if")
        return stmt

    def parse_while_stmt(self) -> WhileStmt:
        """Parse while loop: while(cond) { body }."""
        while_token = self.expect(TokenType.WHILE)
        self.expect(TokenType.LPAREN)
        condition = self.parse_expression()
        self.expect(TokenType.RPAREN)
        self.expect(TokenType.LBRACE)
        body = self.parse_statements()
        self.expect(TokenType.RBRACE)

        stmt = WhileStmt(condition=condition, body=body)
        stmt.set_location(while_token.line, while_token.col, "while")
        return stmt

    def parse_for_stmt(self) -> ForStmt:
        """Parse for loop: for(init; cond; update) { body }."""
        for_token = self.expect(TokenType.FOR)
        self.expect(TokenType.LPAREN)

        # Parse init (may be empty)
        init = None
        if not self.match(TokenType.SEMICOLON):
            init = self.parse_expr_stmt()
        else:
            self.advance()

        # Parse condition
        condition = self.parse_expression()
        self.expect(TokenType.SEMICOLON)

        # Parse update (may be empty)
        update = None
        if not self.match(TokenType.RPAREN):
            update = self.parse_expr_stmt()
        self.expect(TokenType.RPAREN)

        self.expect(TokenType.LBRACE)
        body = self.parse_statements()
        self.expect(TokenType.RBRACE)

        stmt = ForStmt(init=init, condition=condition, update=update, body=body)
        stmt.set_location(for_token.line, for_token.col, "for")
        return stmt

    def parse_return_stmt(self) -> ReturnStmt:
        """Parse return statement: return [expr];"""
        return_token = self.expect(TokenType.RETURN)
        value = None
        if not self.match(TokenType.SEMICOLON):
            value = self.parse_expression()
        self.expect(TokenType.SEMICOLON)

        stmt = ReturnStmt(value=value)
        stmt.set_location(return_token.line, return_token.col, "return")
        return stmt

    def parse_block(self) -> Block:
        """Parse block: { stmts }."""
        brace_token = self.current()
        self.expect(TokenType.LBRACE)
        stmts = self.parse_statements()
        self.expect(TokenType.RBRACE)

        block = Block(stmts=stmts)
        if brace_token:
            block.set_location(brace_token.line, brace_token.col, "{}")
        return block

    def parse_expr_stmt(self) -> Stmt:
        """Parse expression statement or assignment: expr; or lhs = rhs;."""
        expr = self.parse_expression()

        if self.match(TokenType.ASSIGN):
            # This is an assignment
            if isinstance(expr, Identifier):
                assign_token = self.current()
                self.advance()
                rhs = self.parse_expression()
                self.expect(TokenType.SEMICOLON)

                stmt = Assignment(target=expr.name, value=rhs)
                stmt.set_location(assign_token.line, assign_token.col, "=")
                return stmt
            elif isinstance(expr, Load):
                # Memory store: @addr = value
                assign_token = self.current()
                self.advance()
                rhs = self.parse_expression()
                self.expect(TokenType.SEMICOLON)

                stmt = Store(address=expr.address, value=rhs)
                stmt.set_location(assign_token.line, assign_token.col, "!")
                return stmt

        # Plain expression statement
        self.expect(TokenType.SEMICOLON)
        return ExprStmt(expr=expr)

    # ========================================================================
    # Expression Parsing (Precedence Climbing)
    # ========================================================================

    def parse_expression(self) -> Expr:
        """Parse expression (entry point)."""
        return self.parse_logical_or()

    def parse_logical_or(self) -> Expr:
        """Parse logical OR: expr | expr."""
        left = self.parse_logical_and()
        while self.match(TokenType.BITOR):
            op_token = self.current()
            self.advance()
            right = self.parse_logical_and()
            left = BinaryOp(op="|", left=left, right=right)
            left.set_location(op_token.line, op_token.col, "|")
        return left

    def parse_logical_and(self) -> Expr:
        """Parse logical AND: expr & expr."""
        left = self.parse_comparison()
        while self.match(TokenType.BITAND):
            op_token = self.current()
            self.advance()
            right = self.parse_comparison()
            left = BinaryOp(op="&", left=left, right=right)
            left.set_location(op_token.line, op_token.col, "&")
        return left

    def parse_comparison(self) -> Expr:
        """Parse comparison: ==, !=, <, <=, >, >=."""
        left = self.parse_additive()
        while self.match(TokenType.EQ, TokenType.NE, TokenType.LT,
                          TokenType.LE, TokenType.GT, TokenType.GE):
            op_token = self.current()
            op = op_token.value
            self.advance()
            right = self.parse_additive()
            left = BinaryOp(op=op, left=left, right=right)
            left.set_location(op_token.line, op_token.col, op)
        return left

    def parse_additive(self) -> Expr:
        """Parse addition/subtraction: +, -."""
        left = self.parse_multiplicative()
        while self.match(TokenType.PLUS, TokenType.MINUS):
            op_token = self.current()
            op = op_token.value
            self.advance()
            right = self.parse_multiplicative()
            left = BinaryOp(op=op, left=left, right=right)
            left.set_location(op_token.line, op_token.col, op)
        return left

    def parse_multiplicative(self) -> Expr:
        """Parse multiplication/division/modulo: *, /, %."""
        left = self.parse_unary()
        while self.match(TokenType.STAR, TokenType.SLASH, TokenType.MOD):
            op_token = self.current()
            op = op_token.value
            self.advance()
            right = self.parse_unary()
            left = BinaryOp(op=op, left=left, right=right)
            left.set_location(op_token.line, op_token.col, op)
        return left

    def parse_unary(self) -> Expr:
        """Parse unary operations: -, ~, @(load)."""
        if self.match(TokenType.MINUS):
            op_token = self.current()
            self.advance()
            operand = self.parse_unary()
            expr = UnaryOp(op="-", operand=operand)
            expr.set_location(op_token.line, op_token.col, "-")
            return expr
        elif self.match(TokenType.BITNOT):
            op_token = self.current()
            self.advance()
            operand = self.parse_unary()
            expr = UnaryOp(op="~", operand=operand)
            expr.set_location(op_token.line, op_token.col, "~")
            return expr
        elif self.match(TokenType.BITAND):
            # Memory load: @addr
            op_token = self.current()
            self.advance()
            operand = self.parse_unary()
            expr = Load(address=operand)
            expr.set_location(op_token.line, op_token.col, "@")
            return expr
        return self.parse_postfix()

    def parse_postfix(self) -> Expr:
        """Parse postfix operations: function calls, array indexing."""
        expr = self.parse_primary()
        while True:
            if self.match(TokenType.LPAREN):
                # Function call
                paren_token = self.current()
                self.advance()
                args = []
                while not self.match(TokenType.RPAREN):
                    args.append(self.parse_expression())
                    if self.match(TokenType.COMMA):
                        self.advance()
                self.expect(TokenType.RPAREN)

                if isinstance(expr, Identifier):
                    expr = Call(name=expr.name, args=args)
                    expr.set_location(paren_token.line, paren_token.col, "()")
            elif self.match(TokenType.LBRACKET):
                # Array indexing
                bracket_token = self.current()
                self.advance()
                index = self.parse_expression()
                self.expect(TokenType.RBRACKET)

                from .base_parser import Index
                expr = Index(expr=expr, index=index)
                expr.set_location(bracket_token.line, bracket_token.col, "[]")
            else:
                break
        return expr

    def parse_primary(self) -> Expr:
        """Parse primary expressions: literals, identifiers, parenthesized expressions."""
        if self.match(TokenType.NUMBER):
            num_token = self.current()
            value = int(num_token.value) if '.' not in num_token.value else float(num_token.value)
            self.advance()
            expr = Literal(value=value, type_hint="number")
            expr.set_location(num_token.line, num_token.col, num_token.value)
            return expr

        elif self.match(TokenType.STRING):
            str_token = self.current()
            value = str_token.value
            self.advance()
            expr = Literal(value=value, type_hint="string")
            expr.set_location(str_token.line, str_token.col, str_token.value)
            return expr

        elif self.match(TokenType.CHAR):
            char_token = self.current()
            value = ord(char_token.value[0]) if char_token.value else 0
            self.advance()
            expr = Literal(value=value, type_hint="char")
            expr.set_location(char_token.line, char_token.col, char_token.value)
            return expr

        elif self.match(TokenType.IDENTIFIER):
            id_token = self.current()
            name = id_token.value
            self.advance()
            expr = Identifier(name=name)
            expr.set_location(id_token.line, id_token.col, name)
            return expr

        elif self.match(TokenType.LPAREN):
            paren_token = self.current()
            self.advance()
            expr = self.parse_expression()
            self.expect(TokenType.RPAREN)
            expr.set_location(paren_token.line, paren_token.col, "()")
            return expr

        else:
            self.error("Expected expression (literal, identifier, or parenthesized expression)")


def parse_bcpl(source: str) -> Program:
    """Parse BCPL source code → AST with source locations."""
    lexer = BCPLLexer(source)
    tokens = lexer.tokenize()
    parser = BCPLParser(tokens)
    return parser.parse()
