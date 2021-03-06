import ceylon.interop.java {
    CeylonIterable
}
import ceylon.json {
    JsonArray=Array,
    JsonObject=Object
}

import com.redhat.ceylon.compiler.typechecker {
    TypeChecker
}
import com.redhat.ceylon.compiler.typechecker.tree {
    Node,
    Tree,
    Visitor
}
import com.redhat.ceylon.model.typechecker.model {
    Class,
    Declaration,
    DeclarationWithProximity,
    Function,
    Functional,
    ParameterList,
    Scope,
    Setter,
    Type,
    TypeDeclaration,
    TypeParameter,
    Unit,
    Value
}

import java.lang {
    JString=String
}
import java.util {
    JMap=Map,
    JHashMap=HashMap,
    JList=List
}

class Autocompleter(String file, 
    Integer row, Integer col, 
    TypeChecker checker) {
    
    shared [Node,String]? selectedNode {
        for (pu in CeylonIterable(checker.phasedUnits.phasedUnits)) {
            if (file.equals(pu.unitFile.name)) {
                value fiv = FindIdentifierVisitor(row,col);
                pu.compilationUnit.visit(fiv);
                if (exists [node, text] = fiv.result) {
                    value fpv = FindParentVisitor(node);
                    pu.compilationUnit.visit(fpv);
                    return [fpv.node, text];
                }
            }
        }
        return null;
    }
    
    shared JsonArray completions {
        if (exists [node, prefix] = selectedNode) {
            Unit unit = node.unit;
            Scope scope = node.scope;
            JMap<JString,DeclarationWithProximity> completions;
            switch (node)
            case (is Tree.QualifiedMemberOrTypeExpression) {
                Tree.QualifiedMemberOrTypeExpression exp = node;
                Tree.Primary p = exp.primary;
                if (exp.staticMethodReference) {
                    assert (is Tree.StaticMemberOrTypeExpression smte = p);
                    assert (is TypeDeclaration td = smte.declaration);
                    completions = td.getMatchingMemberDeclarations(unit, scope, prefix, 0);
                }
                else {
                    Type type;
                    if (exists t = p.typeModel) {
                        switch (op = exp.memberOperator)
                        case (is Tree.SafeMemberOp) {
                            type = unit.getDefiniteType(t);
                        }
                        case (is Tree.SpreadOp) {
                            type = unit.getIteratedType(t);
                        }
                        else {
                            type = t;
                        }
                        completions = type.declaration.getMatchingMemberDeclarations(unit, scope, prefix, 0);
                    }
                    else {
                        completions = JHashMap<JString,DeclarationWithProximity>();
                    }
                }
            }
            case (is Tree.BaseMemberOrTypeExpression) {
                completions = node.scope.getMatchingDeclarations(unit, prefix, 0);
            }
            case (is Tree.BaseType) {
                completions = node.scope.getMatchingDeclarations(unit, prefix, 0);
            }
            case (is Tree.QualifiedType) {
                if (exists type = node.outerType.typeModel) {
                    completions = type.declaration.getMatchingMemberDeclarations(unit, scope, prefix, 0);
                }
                else {
                    completions = JHashMap<JString,DeclarationWithProximity>(); 
                }
            }
            case (is Tree.Variable) {
                completions = node.scope.getMatchingDeclarations(unit, prefix, 0);
            }
            else {
                //TODO!!
                completions = JHashMap<JString,DeclarationWithProximity>();
            }
            
            return translateCompletions(completions);
        }
        else {
            return JsonArray();
        }
    }
    
    JsonArray translateCompletions(JMap<JString,DeclarationWithProximity> comps) {
        value completions = JsonArray();
        for (entry in CeylonIterable(comps.entrySet())) {
            translateCompletion(entry.\ivalue, completions);
        }
        return completions;
    }
    
    void translateCompletion(DeclarationWithProximity dwp, JsonArray completions) {
        value declaration = dwp.declaration;
        if (declaration is TypeDeclaration || !(declaration is Functional)) {
            value completion = constructCompletion(declaration, false);
            if (!completions.contains(completion)) {
                completions.add(completion);
            }
        }
        
        if (is Functional declaration) {
            value completion = constructCompletion(declaration, true);
            if (!completions.contains(completion)) {
                completions.add(completion);
            }
        }
    }
    
    JsonObject constructCompletion(Declaration declaration, Boolean withArgs) {
        value completion = JsonObject();
        StringBuilder insert = StringBuilder();
        StringBuilder display = StringBuilder();
        if(is Function declaration) {
            Function m = declaration;
            insert.append(m.name);
            if (m.annotation) {
                display.append(annotationId).append(m.name).append(end);
                if (!m.firstParameterList.parameters.empty) {
                    addParameterLists(display, insert, m.parameterLists);
                }
            }
            else {
                display.append(variableId).append(m.name).append(end);
                if (withArgs) {
                    addParameterLists(display, insert, m.parameterLists);
                }
                else {
                    addTypeParameters(display, insert, m.typeParameters);
                }
            }
        }
        else if (is Class declaration) {
            Class c = declaration;
            insert.append(c.name);
            display.append(typeId).append(c.name).append(end);
            if (withArgs) {
                addParameterLists(display, insert, c.parameterLists);
            }
            else {
                addTypeParameters(display, insert, c.typeParameters);
            }
        }
        else if (declaration is Value || declaration is Setter){
            insert.append(declaration.name);
            display.append(variableId).append(declaration.name).append(end);
        }
        else if (is TypeDeclaration declaration){
            insert.append(declaration.name);
            display.append(typeId).append(declaration.name).append(end);
            if (!withArgs) {
                TypeDeclaration td = declaration;
                addTypeParameters(display, insert, td.typeParameters);
            }
        }
        else {
            insert.append(declaration.name);
            display.append(declaration.name);
        }
        completion.put("insert", insert.string);
        completion.put("display", display.string);
        completion.put("help", 
            getSignature(declaration) + 
                    getExtraInfo(declaration) + 
                    getDoc(declaration) + 
                    getParameterInfo(declaration));
        return completion;
    }
    
    void addTypeParameters(StringBuilder display, StringBuilder insert, 
        JList<TypeParameter> typeParameters) {
        if (!typeParameters.empty) {
            insert.append("<");
            display.append("&lt;");
            variable Boolean once = true;
            for (param in CeylonIterable(typeParameters)) {
                if (once) {
                    once = false;
                } else {
                    insert.append(", ");
                    display.append(", ");
                }
                
                insert.append(param.name);
                display.append(typeId).append(param.name).append(end);
            }
            
            insert.append(">");
            display.append("&gt;");
        }
    }
    
    
    void addParameterLists(StringBuilder display, StringBuilder insert, 
        JList<ParameterList> parameterLists) {
        for (parameterList in CeylonIterable(parameterLists)) {
            insert.append("(");
            display.append("(");
            variable Boolean once = true;
            for (param in CeylonIterable(parameterList.parameters)) {
                if (once) {
                    once = false;
                } else {
                    insert.append(", ");
                    display.append(", ");
                }
                
                if (param.declaredVoid) {
                    display.append(keyword).append("void").append(end);
                } else if (exists t = param.type) {
                    value type 
                            = if (param.sequenced) 
                            then t.declaration.unit.getIteratedType(t) 
                            else param.type;
                    display.append(typeId).append(escape(type)).append(end);
                    if (param.sequenced) {
                        display.append(if (param.atLeastOne) then "+" else "*");
                    }
                }
                
                display.append(" ").append(variableId).append(param.name).append(end);
                appendParameters(param.model, display);
                insert.append(param.name);
            }
            
            insert.append(")");
            display.append(")");
        }
    }
    
}

class FindIdentifierVisitor(Integer row, Integer col) 
        extends Visitor() {
    
    shared variable [Node,String]? result = null;
    
    shared actual void visit(Tree.Identifier that) {
        if (that.token.line == row) {
            Integer col0 = that.token.charPositionInLine;
            Integer col1 = col0 + that.text.size;
            if (col >= col0, col <= col1) {
                result = [that, that.text[0:col-col0]];
            }
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.MemberOperator that) {
        if (that.token.line == row) {
            Integer col1 = that.token.charPositionInLine + that.text.size;
            if (col == col1) {
                result = [that, ""];
            }
        }
        
        super.visit(that);
    }
}

class FindParentVisitor(shared variable Node node) 
        extends Visitor() {
    variable Boolean found = false;
    
    shared actual void visitAny(Node node) {
        if (found) {
            return;
        }
        
        super.visitAny(node);
    }
    
    shared actual void visit(Tree.StaticMemberOrTypeExpression that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.QualifiedMemberOrTypeExpression that) {
        if (found) {
            return;
        }
        
        if (exists op = that.memberOperator, op == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.ImportMemberOrType that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.Alias that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.Declaration that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.InitializerParameter that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.SimpleType that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.MemberLiteral that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.SatisfiesCondition that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
    
    shared actual void visit(Tree.NamedArgument that) {
        if (found) {
            return;
        }
        
        if (exists id = that.identifier, id == node) {
            node = that;
            found = true;
            return;
        }
        
        super.visit(that);
    }
}
