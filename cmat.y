%{

extern int yylex();
void yyerror(const char* msg);

int syntax_error = 0;

int indice_tab_str = 0;

%}

%define parse.error verbose //indique le type d'erreur de syntaxe

%code requires {
    #include "global.h"
}


%union 
{
	struct u_tab {
		enum type type_tab;
		int nDim;
		int tailleDim;
		int taillesDim[MAX_DIMENSION_TABLEAU];
		int listeValeursEntieres[64];
		float listeValeursFlottantes[64];
	} tableau;
	
	enum QuadOp op;
	
	char nom[MAX_LENGTH_VAR_NAME];
	
	float constante_flottante;
	int constante_entiere;
	char constante_caractere[MAX_LONGUEUR_VARIABLE];
	
	
	
	struct {
		int indice_demande; //si tableau
		struct noeud* ptr;
	} exprval;
	
	char tab_str[64][MAX_LENGTH_VAR_NAME]; //limite arbitraire : 64 chaînes de 64 caractères max
	
	enum type type;
}

%token INTERV_OP LOGICAL_AND LOGICAL_OR
%token PLUS_ASSIGN MINUS_ASSIGN MULT_ASSIGN DIV_ASSIGN MOD_ASSIGN AND_ASSIGN XOR_ASSIGN OR_ASSIGN
%token LE GE EQ NE 
%token INT FLOAT MATRIX
%token IF ELSE FOR RETURN  
%token MAIN PRINTF PRINT PRINTMAT WHILE
%token <constante_caractere> C_STR
%type <constante_caractere> constante_caractere

%token <nom> IDENT
%type <nom> variable_declaree
%token <op> INCR DECR
%type <tableau> intervalle_dimension liste_tableau liste_nombre rangee liste_rangee liste_entiers liste_flottants valeur_tableau
%type <op> assign
%token <constante_entiere> C_INT 
%token <constante_flottante> C_FLOAT
%type <constante_entiere> constante_entiere 
%type <constante_flottante> constante_flottante
%type <tab_str> liste_variable_declaree

%right '=' PLUS_ASSIGN MINUS_ASSIGN MULT_ASSIGN DIV_ASSIGN MOD_ASSIGN AND_ASSIGN XOR_ASSIGN OR_ASSIGN
%left LOGICAL_OR
%left LOGICAL_AND
%left '|'
%left '^'
%left '&'
%left EQ NE
%left '<' '>'
%left LE GE 
%left '+' '-'
%left '*' '/' '%' 
%left UNARY INTERV_OP
%right INCR DECR

%type <exprval> expression incr_et_decr valeur appel_fonction operation
%type <type> type;

%start programme

%% //grammaire temporaire

//Créer une liste de declaration_fonction si on ajoute les fonction en dehors du main
programme : main {return syntax_error;}
;

main : INT MAIN '(' ')' corps
;

corps : '{' liste_instruction '}' | '{' '}'
;

liste_instruction : liste_instruction instruction 
		   | instruction
;

instruction : declaration_variable ';' 
	    | declaration_fonction
	    | liste_operation ';'
        | condition
        | boucle
	    | RETURN C_INT ';'
;

partie_else : ELSE{gencode(liste_quad, QOP_ELSE_IF, NULL, NULL, NULL);} corps
	| ELSE{gencode(liste_quad, QOP_ELSE_IF, NULL, NULL, NULL);} condition
	| %empty {gencode(liste_quad, QOP_ELSE_IF, NULL, NULL, NULL);}
	;


condition : IF '(' expression {struct noeud* entree = get_symbole(tds, $3.ptr->info.nom); gencode(liste_quad, QOP_IF, NULL, NULL, entree);} ')' corps{gencode(liste_quad, QOP_HALF_IF, NULL, NULL, NULL);} partie_else{gencode(liste_quad, QOP_END_IF, NULL, NULL, NULL);}
;

boucle : boucle_for | boucle_while
;

/*Vrai boucle for, mais pas celle qui est demandé
boucle_for : FOR '(' initial_declaration ';' liste_operation ';' liste_operation ')' corps
;

initial_declaration : declaration_variable | liste_operation
;*/

// Boucle for moins poussée
boucle_for : FOR '(' type IDENT {struct noeud* entree = get_symbole(tds, $4); 
			if(entree == NULL) {
				entree = insertion(&tds, $4, SORTE_VARIABLE, $3); $<exprval>$.ptr = entree; /* $$ = noeud entrée */
				$<exprval>$.ptr = entree; /* $$ = noeud entrée */
			}
			else 
			{
				fprintf(stderr,"Previous declaration of %s exists\n", $4); 
               	 	exit(1);
               	}
} 
'=' expression {struct noeud* entree = get_symbole(tds, $7.ptr->info.nom); gencode(liste_quad, QOP_FOR, entree, NULL, $<exprval>5.ptr);}
';' expression {gencode(liste_quad, QOP_HALF_FOR, NULL, NULL, $10.ptr);} ';' incr_et_decr ')' corps{gencode(liste_quad, QOP_END_FOR, NULL, NULL, NULL);}
;

boucle_while : WHILE '(' {gencode(liste_quad, QOP_WHILE, NULL, NULL, NULL);} expression {
			struct noeud* entree = get_symbole(tds, $4.ptr->info.nom); 
			if(entree == NULL) 
			{
				char err_msg[MAX_LENGTH_VAR_NAME + 20];
				sprintf(err_msg, "Undeclared name : '%s'", $4.ptr->info.nom);
				yyerror(err_msg);
				entree = insertion(&tds, $4.ptr->info.nom, SORTE_NONE, TYPE_ERROR);
			}
               }
 ')' {gencode(liste_quad, QOP_HALF_WHILE, NULL, NULL, $4.ptr);} corps{gencode(liste_quad, QOP_END_WHILE, NULL, NULL, NULL);}
;


declaration_variable : type liste_variable_declaree 
	{
		for(int i = 0; i < indice_tab_str; i++) 
		{ //mettre le type dans la tds
			struct noeud* noeud = get_symbole(tds, $2[i]);
			if(noeud != NULL)
				noeud->info.type = $1;
		}
	}
;

liste_variable_declaree : liste_variable_declaree ',' variable_declaree {strcpy($$[indice_tab_str], $3); indice_tab_str += 1;}
			| variable_declaree {strcpy($$[indice_tab_str], $1); indice_tab_str += 1;}
;

variable_declaree : 
	IDENT {struct noeud* entree = insertion(&tds, $1, SORTE_VARIABLE, TYPE_NONE); /*strcpy($$, $1);*/}
    | IDENT '=' expression {
    
		struct noeud* entree = insertion(&tds, $1, SORTE_VARIABLE, TYPE_NONE);
            if(entree == NULL) {
                fprintf(stderr,"Previous declaration of %s exists\n", $1); 
                exit(1);
            }
        		
        	if($3.ptr->info.sorte == SORTE_TABLEAU)
        	{		
        		struct noeud* indice;
        		//if($3.ptr->info.type == TYPE_INT)
				indice = get_symbole_constante_int(tds, $3.indice_demande);
			/*else if($3.ptr->info.type == TYPE_FLOAT)
			{
				indice = get_symbole_constante(tds, $3.indice_demande);
			}*/
				
			gencode(liste_quad, QOP_ASSIGN, $3.ptr, indice, entree);
        	}
        	else
        	{
			gencode(liste_quad, QOP_ASSIGN, $3.ptr, NULL, entree);
		}
			
			//strcpy($$, $1);
		}
    | IDENT intervalle_dimension {struct noeud* entree = insertion_tableau(&tds, $1, TYPE_NONE, $2.nDim, $2.taillesDim); 
    
    		if(entree == NULL) {
                fprintf(stderr,"Previous declaration of %s exists\n", $1); 
                exit(1);
            }}
    | IDENT intervalle_dimension '=' valeur_tableau {
    
    		struct noeud* entree = insertion_tableau(&tds, $1, $4.type_tab, $2.nDim, $2.taillesDim); 
    
    		if(entree == NULL) 
    		{
               	fprintf(stderr,"Previous declaration of %s exists\n", $1); 
                	exit(1);
		}
		
		if(entree->info.type == TYPE_INT)
		{
			//taille dimension 1
		    for(int i = 0; i < $2.taillesDim[0]; i++)
		    {
		    	entree->info.tableau.valeurs_entieres_tableau[i] = $4.listeValeursEntieres[i];
		    }
		}
		else if(entree->info.type == TYPE_FLOAT)
		{
			//taille dimension 1
		    for(int i = 0; i < $2.taillesDim[0]; i++)
		    {
		    	entree->info.tableau.valeurs_flottantes_tableau[i] = $4.listeValeursFlottantes[i];
		    }
		}
            
            gencode(liste_quad, QOP_ASSIGN_TAB, NULL, NULL, entree);
}
;


liste_operation : 
	liste_operation ',' operation
	| operation
;

operation : expression {$$.ptr = $1.ptr;}
	| IDENT assign operation {struct noeud* entree = get_symbole(tds, $1);
	
				  //TODO : switch case pour les différents types de QOP_ASSIGN
	
				  gencode(liste_quad, QOP_ASSIGN, $3.ptr, NULL, entree);
				  $$.ptr = entree;}
	| IDENT intervalle_dimension assign operation {}
;

declaration_fonction : 
	type IDENT '(' liste_parametre ')' corps
    | type IDENT '(' ')' corps
;
		 
appel_fonction : 
	IDENT '(' liste_argument ')' {}
        | IDENT '(' ')' {}
	| PRINTF '(' constante_caractere ')' {
				struct noeud* entree = get_symbole_constante_str(tds, $3);
				gencode(liste_quad, QOP_PRINTF, NULL, NULL, entree);
				$$.ptr = entree;}
	| PRINT '(' constante_entiere ')' {
				struct noeud* entree = get_symbole_constante_int(tds, $3);
				gencode(liste_quad, QOP_PRINT, NULL, NULL, entree);
				$$.ptr = entree;}
	| PRINT '(' constante_flottante ')' {
				struct noeud* entree = get_symbole_constante(tds, $3);
				gencode(liste_quad, QOP_PRINT, NULL, NULL, entree);
				$$.ptr = entree;}
        | PRINT '(' IDENT ')' {
        			struct noeud* entree = get_symbole(tds, $3);
				gencode(liste_quad, QOP_PRINT, NULL, NULL, entree);
				$$.ptr = entree;
				}
	| PRINTMAT '(' IDENT ')' {}
;
            
liste_parametre : liste_parametre ',' parametre | parametre
;

liste_argument : liste_argument ',' argument | argument
;

parametre : type IDENT
;

argument :  IDENT assign expression 
	| expression
; 

expression : 
	valeur {
			struct noeud* entree;
			if($1.ptr->info.sorte == SORTE_CONSTANTE) {
				if($1.ptr->info.type == TYPE_INT)
					entree = get_symbole_constante_int(tds, $1.ptr->info.valeur_entiere);
				else if($1.ptr->info.type == TYPE_FLOAT)
					entree = get_symbole_constante(tds, $1.ptr->info.valeur_flottante);
			} else entree = get_symbole(tds, $1.ptr->info.nom);
			
			$$.ptr = entree;
		}
	| expression '+' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if(($1.ptr->info.sorte == SORTE_TABLEAU && $1.ptr->info.type != TYPE_MATRIX) || ($3.ptr->info.sorte == SORTE_TABLEAU && $3.ptr->info.type != TYPE_MATRIX)) {
				yyerror("+ avec des tableaux");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($3.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_PLUS, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_PLUS, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_PLUS, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_PLUS, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
	| expression '-' expression {          
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if(($1.ptr->info.sorte == SORTE_TABLEAU && $1.ptr->info.type != TYPE_MATRIX) || ($3.ptr->info.sorte == SORTE_TABLEAU && $3.ptr->info.type != TYPE_MATRIX)) {
				yyerror("- avec des tableaux");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($3.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_MINUS, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_MINUS, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_MINUS, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_MINUS, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression '*' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if(($1.ptr->info.sorte == SORTE_TABLEAU && $1.ptr->info.type != TYPE_MATRIX) || ($3.ptr->info.sorte == SORTE_TABLEAU && $3.ptr->info.type != TYPE_MATRIX)) {
				yyerror("* avec des tableaux");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($3.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_MULT, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_MULT, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_MULT, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_MULT, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression '/' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if(($1.ptr->info.sorte == SORTE_TABLEAU && $1.ptr->info.type != TYPE_MATRIX) || ($3.ptr->info.sorte == SORTE_TABLEAU && $3.ptr->info.type != TYPE_MATRIX)) {
				yyerror("/ avec des tableaux");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($3.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_DIV, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_DIV, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_DIV, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_DIV, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression '%' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type != TYPE_INT || $1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.type != TYPE_INT || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("\% avec des non entiers");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_MOD, $1.ptr, $3.ptr, $$.ptr);
			}
		}
    | expression '^' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type != TYPE_INT || $1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.type != TYPE_INT || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("^ avec des non entiers");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_XOR, $1.ptr, $3.ptr, $$.ptr);
			}
		}
    | expression '&' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type != TYPE_INT || $1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.type != TYPE_INT || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("& avec des non entiers");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_AND, $1.ptr, $3.ptr, $$.ptr);
			}
		}
    | expression '|' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type != TYPE_INT || $1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.type != TYPE_INT || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("| avec des non entiers");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_OR, $1.ptr, $3.ptr, $$.ptr);
			}
		}
    | expression '>' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) 
			{
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} 
			else if($1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.sorte == SORTE_TABLEAU) 
			{
				yyerror("> avec des tableaux/matrices");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} 
			else if($1.ptr->info.type == TYPE_FLOAT) 
			{
				$$.ptr = newtemp(&tds, TYPE_INT);
				if ($3.ptr->info.type == TYPE_INT) 
				{
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_GT, $1.ptr, tmp, $$.ptr);
				} 
				else 
				{
					gencode(liste_quad, QOP_GT, $1.ptr, $3.ptr, $$.ptr);
				}
			} 
			else if ($3.ptr->info.type == TYPE_FLOAT)
			{
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_GT, $1.ptr, tmp, $$.ptr);
			} 
			else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) 
			{
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_GT, $1.ptr, $3.ptr, $$.ptr);
			} 
			else 
			{
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression '<' expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("< avec des tableaux/matrices");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_LT, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_LT, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_LT, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_LT, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression LE expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("<= avec des tableaux/matrices");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_LE, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_LE, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_LE, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_LE, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression GE expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror(">= avec des tableaux/matrices");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_GE, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_GE, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_GE, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_GE, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression EQ expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("== avec des tableaux/matrices");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_EQ, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_EQ, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_EQ, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_EQ, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression NE expression {
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("!= avec des tableaux/matrices");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				if ($3.ptr->info.type == TYPE_INT) {
					struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
					gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
					gencode(liste_quad, QOP_NE, $1.ptr, tmp, $$.ptr);
				} else {
					gencode(liste_quad, QOP_NE, $1.ptr, $3.ptr, $$.ptr);
				}
			} else if ($3.ptr->info.type == TYPE_FLOAT){
				struct noeud *tmp = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_CAST, $3.ptr, NULL, tmp);
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_NE, $1.ptr, tmp, $$.ptr);
			} else if($1.ptr->info.type == TYPE_INT && $3.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_NE, $1.ptr, $3.ptr, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | expression LOGICAL_AND expression { //à revoir parce que le AND n'existe pas en MIPS
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type != TYPE_INT || $1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.type != TYPE_INT || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("&& avec des non entiers");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_AND, $1.ptr, $3.ptr, $$.ptr);
			}
		}
	| expression LOGICAL_OR expression {//à revoir parce que le OR n'existe pas en MIPS
			if($1.ptr->info.type == TYPE_ERROR || $3.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($1.ptr->info.type != TYPE_INT || $1.ptr->info.sorte == SORTE_TABLEAU || $3.ptr->info.type != TYPE_INT || $3.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("|| avec des non entiers");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_OR, $1.ptr, $3.ptr, $$.ptr);
			}
		}
    | '-' expression %prec UNARY {
			if($2.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($2.ptr->info.sorte == SORTE_TABLEAU && $2.ptr->info.type != TYPE_MATRIX) {
				yyerror("- avec un tableau");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($2.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($2.ptr->info.type == TYPE_FLOAT) {
				$$.ptr = newtemp(&tds, TYPE_FLOAT);
				gencode(liste_quad, QOP_UNARY_MINUS, $2.ptr, NULL, $$.ptr);
			} else if($2.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_UNARY_MINUS, $2.ptr, NULL, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | '+' expression %prec UNARY {
			$$ = $2;
		}
    | '!' expression %prec UNARY {
			if($2.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($2.ptr->info.sorte == SORTE_TABLEAU) {
				yyerror("! avec un tableau/une matrice");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($2.ptr->info.type == TYPE_FLOAT || $2.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_NOT, $2.ptr, NULL, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    | '~' expression %prec UNARY {
			if($2.ptr->info.type == TYPE_ERROR) {
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($2.ptr->info.sorte == SORTE_TABLEAU && $2.ptr->info.type != TYPE_MATRIX) {
				yyerror("~ avec un tableau");
				$$.ptr = newtemp(&tds, TYPE_ERROR);
			} else if($2.ptr->info.type == TYPE_FLOAT) {
				yyerror("~ avec un flottant");
			} else if($2.ptr->info.type == TYPE_MATRIX) {
				//$$.ptr = newtemp(&tds, TYPE_ERROR); => pas encore géré
			} else if($2.ptr->info.type == TYPE_INT) {
				$$.ptr = newtemp(&tds, TYPE_INT);
				gencode(liste_quad, QOP_NEG, $2.ptr, NULL, $$.ptr);
			} else {
				$$.ptr = newtemp(&tds, TYPE_NONE);
			}
		}
    /*| '*' expression %prec UNARY   
    | '&' expression %prec UNARY*/
    | '(' expression ')' {$$ = $2;}
;

       
intervalle_dimension : 
	intervalle_dimension '[' liste_rangee ']' {$$.nDim = $1.nDim + 1; $$.taillesDim[0] = $1.tailleDim; $$.taillesDim[1] = $3.tailleDim;} 
    | '[' liste_rangee ']' {$$.type_tab = $2.type_tab; $$.nDim = 1; $$.tailleDim = $2.tailleDim; $$.taillesDim[0] = $2.tailleDim;} 
;

liste_rangee : 
	liste_rangee ';' rangee { $$.nDim = $1.nDim + 1;}
    | rangee {$$ = $1; $$.nDim = 1;}
;

rangee : '*' {$$.type_tab = TYPE_MATRIX; /*Matrix exclusivement*/} 
        | expression INTERV_OP expression {$$.type_tab = TYPE_NONE;}
        | expression {$$.tailleDim = $1.ptr->info.valeur_entiere; $$.type_tab = TYPE_NONE;}
;

valeur_tableau : '{' liste_nombre '}' {$$.type_tab = $2.type_tab; 
					
					if($2.type_tab == TYPE_INT)
						memcpy($$.listeValeursEntieres, $2.listeValeursEntieres, 64*sizeof(int));
					else if($2.type_tab == TYPE_FLOAT)
						memcpy($$.listeValeursFlottantes, $2.listeValeursFlottantes, 64*sizeof(float));
					
					/*$$ = $2; $$.nDim = 1;*/
					
					}
		| '{' liste_tableau '}' {$$ = $2; $$.nDim = $2.nDim + 1;}
;
		
liste_tableau : liste_tableau ',' valeur_tableau {$$.nDim = ($1.nDim >= $3.nDim ? $1.nDim : $3.nDim);
}
		| valeur_tableau {$$ = $1;}
;

liste_nombre : liste_entiers {$$.type_tab = TYPE_INT;} | liste_flottants {$$.type_tab = TYPE_FLOAT;}
;

liste_flottants : liste_flottants ',' constante_flottante {/*tab[1], ...*/ static int indice = 1; $$.listeValeursFlottantes[indice] = $3; indice += 1;}
		 | constante_flottante {/*tab[0]*/ $$.listeValeursFlottantes[0] = $1;}
;

liste_entiers : liste_entiers ',' constante_entiere {/*tab[1], ...*/ static int indice = 1; $$.listeValeursEntieres[indice] = $3; indice += 1;}
		| constante_entiere {/*tab[0]*/ $$.listeValeursEntieres[0] = $1;}
;

type : INT {$$ = TYPE_INT;} | FLOAT {$$ = TYPE_FLOAT;} | MATRIX {$$ = TYPE_MATRIX;}
;

valeur : 
	IDENT {
			struct noeud* entree = get_symbole(tds, $1); 
			if(entree == NULL) {
				char err_msg[MAX_LENGTH_VAR_NAME + 20];
				sprintf(err_msg, "Undeclared name : '%s'", $1);
				yyerror(err_msg);
				entree = insertion(&tds, $1, SORTE_NONE, TYPE_ERROR);
			}
			$$.ptr = entree;
		}	
	| constante_entiere {
        	struct noeud* entree = get_symbole_constante_int(tds, $1);
		    $$.ptr = entree;
		}
	| constante_flottante {
			struct noeud* entree = get_symbole_constante(tds, $1);	
			$$.ptr = entree;
		}
    | IDENT intervalle_dimension {
    			struct noeud* entree = get_symbole(tds, $1); //tableau récupéré
			if(entree == NULL) {
				char err_msg[MAX_LENGTH_VAR_NAME + 20];
				sprintf(err_msg, "Undeclared name : '%s'", $1);
				yyerror(err_msg);
				entree = insertion(&tds, $1, SORTE_NONE, TYPE_ERROR);
			}
			$$.indice_demande = $2.tailleDim; 
			$$.ptr = entree;}
    | incr_et_decr {
			struct noeud* entree = get_symbole(tds, $1.ptr->info.nom); 
		    if(entree == NULL) {
				entree = insertion(&tds, $1.ptr->info.nom, SORTE_VARIABLE, TYPE_NONE);
			}
			$$.ptr = entree;
		}
    | appel_fonction {} 
;

incr_et_decr : 
	IDENT INCR {
			$2 = QOP_POST_INCR; 
			struct noeud* entree = get_symbole(tds, $1); 
			if(entree == NULL) {
				char err_msg[MAX_LENGTH_VAR_NAME + 20];
				sprintf(err_msg, "Undeclared name : '%s'", $1);
				yyerror(err_msg);
				entree = insertion(&tds, $1, SORTE_NONE, TYPE_ERROR);
			}
			gencode(liste_quad, $2, entree, NULL, entree);
			$$.ptr = entree;
		}
	| IDENT DECR {
			$2 = QOP_POST_DECR;
	     	struct noeud* entree = get_symbole(tds, $1); 
			if(entree == NULL) {
				char err_msg[MAX_LENGTH_VAR_NAME + 20];
				sprintf(err_msg, "Undeclared name : '%s'", $1);
				yyerror(err_msg);
				entree = insertion(&tds, $1, SORTE_NONE, TYPE_ERROR);
			}
			gencode(liste_quad, $2, entree, NULL, entree);
			$$.ptr = entree; 
		}
	| INCR IDENT {
			$1 = QOP_PRE_INCR;
	     	struct noeud* entree = get_symbole(tds, $2); 
			if(entree == NULL) {
				char err_msg[MAX_LENGTH_VAR_NAME + 20];
				sprintf(err_msg, "Undeclared name : '%s'", $2);
				yyerror(err_msg);
				entree = insertion(&tds, $2, SORTE_NONE, TYPE_ERROR);
			}
			gencode(liste_quad, $1, entree, NULL, entree);
			$$.ptr = entree;
		}
	| DECR IDENT {
			$1 = QOP_PRE_DECR;
	     	struct noeud* entree = get_symbole(tds, $2); 
			if(entree == NULL) {
				char err_msg[MAX_LENGTH_VAR_NAME + 20];
				sprintf(err_msg, "Undeclared name : '%s'", $2);
				yyerror(err_msg);
				entree = insertion(&tds, $2, SORTE_NONE, TYPE_ERROR);
			}
			gencode(liste_quad, $1, entree, NULL, entree);
			$$.ptr = entree;
		}
;

constante_entiere : C_INT {
			struct noeud* entree = insertion_constante(&tds, TYPE_INT, $1);
			$$ = $1;
		} 
;

constante_flottante : C_FLOAT {
			struct noeud* entree = insertion_constante(&tds, TYPE_FLOAT, $1);
			$$ = $1;
		} 
;

constante_caractere : C_STR {
			struct noeud* entree = insertion_constante_str(&tds, TYPE_STR, $1);
			strcpy($$, $1);
		} 
;

assign : '=' {$$ = QOP_ASSIGN;}
	| PLUS_ASSIGN {$$ = QOP_PLUS_ASSIGN;}
	| MINUS_ASSIGN {$$ = QOP_MINUS_ASSIGN;}
	| MULT_ASSIGN {$$ = QOP_MULT_ASSIGN;}
	| DIV_ASSIGN {$$ = QOP_DIV_ASSIGN;}
	| MOD_ASSIGN {$$ = QOP_MOD_ASSIGN;}
	| AND_ASSIGN {$$ = QOP_AND_ASSIGN;}
	| XOR_ASSIGN {$$ = QOP_XOR_ASSIGN;}
	| OR_ASSIGN {$$ = QOP_OR_ASSIGN;}
;


            
%%  

void yyerror(const char* msg)
{
    syntax_error = 1;
	fprintf(stderr, "Syntax error : %s\n", msg);
}
