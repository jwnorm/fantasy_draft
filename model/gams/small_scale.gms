* Fantasy Baseball Draft - Small Scale Example

Sets
i 'players'
/
"Ronald Acuña Jr."
"Mookie Betts"
"Aaron Judge"
"Juan Soto"
"Fernando Tatis Jr."
"Adley Rutschman"
"Yordan Alvarez"
"Bobby Witt Jr."
"Corey Seager"
"Will Smith"
"Julio Rodríguez"
"Shohei Ohtani"
"José Ramírez"
"Freddie Freeman"
"Austin Riley"
"Alex Bregman"
"Corbin Carroll"
"Rafael Devers"
"Gunnar Henderson"
"Mike Trout"
"Francisco Lindor"
"Vladimir Guerrero Jr."
"Sean Murphy"
"William Contreras"
"Kyle Tucker"
"Trea Turner"
"Bryce Harper"
"Marcus Semien"
"Dansby Swanson"
"Matt Olson"
"Cal Raleigh"
"Matt Chapman"
"Ketel Marte"
"Gleyber Torres"
"Michael Harris II"
"Jose Altuve"
"J.T. Realmuto"
"Manny Machado"
"Jonah Heim"
"Willy Adames"
/

j 'round in draft' /1*5/;

Parameters
HR(i)  'projected home runs for player i'
/
"Ronald Acuña Jr."  38
"Mookie Betts"  32
"Aaron Judge"   45
"Juan Soto" 36
"Fernando Tatis Jr."    36
"Adley Rutschman"   18
"Yordan Alvarez"    39
"Bobby Witt Jr."    31
"Corey Seager"  31
"Will Smith"    23
"Julio Rodríguez"   31
"Shohei Ohtani" 39
"José Ramírez"  27
"Freddie Freeman"   26
"Austin Riley"  38
"Alex Bregman"  24
"Corbin Carroll"    21
"Rafael Devers" 36
"Gunnar Henderson"  25
"Mike Trout"    35
"Francisco Lindor"  28
"Vladimir Guerrero Jr." 35
"Sean Murphy"   22
"William Contreras" 22
"Kyle Tucker"   29
"Trea Turner"   22
"Bryce Harper"  27
"Marcus Semien" 28
"Dansby Swanson"    26
"Matt Olson"    40
"Cal Raleigh"   26
"Matt Chapman"  29
"Ketel Marte"   22
"Gleyber Torres"    25
"Michael Harris II" 21
"Jose Altuve"   23
"J.T. Realmuto" 21
"Manny Machado" 29
"Jonah Heim"    19
"Willy Adames"  28
/


R(i) ' projected runs scored for player i'
/
"Ronald Acuña Jr."    126
"Mookie Betts"  106
"Aaron Judge"   101
"Juan Soto" 108
"Fernando Tatis Jr."    107
"Adley Rutschman"   77
"Yordan Alvarez"    98
"Bobby Witt Jr."    108
"Corey Seager"  82
"Will Smith"    73
"Julio Rodríguez"   103
"Shohei Ohtani" 109
"José Ramírez"  94
"Freddie Freeman"   103
"Austin Riley"  100
"Alex Bregman"  89
"Corbin Carroll"    101
"Rafael Devers" 91
"Gunnar Henderson"  85
"Mike Trout"    84
"Francisco Lindor"  90
"Vladimir Guerrero Jr." 97
"Sean Murphy"   65
"William Contreras" 73
"Kyle Tucker"   101
"Trea Turner"   96
"Bryce Harper"  94
"Marcus Semien" 95
"Dansby Swanson"    87
"Matt Olson"    99
"Cal Raleigh"   60
"Matt Chapman"  79
"Ketel Marte"   83
"Gleyber Torres"    85
"Michael Harris II" 89
"Jose Altuve"   87
"J.T. Realmuto" 72
"Manny Machado" 80
"Jonah Heim"    55
"Willy Adames"  79
/

RBI(i) 'projected runs batted in for player i'
/
"Ronald Acuña Jr."  102
"Mookie Betts"  100
"Aaron Judge"   110
"Juan Soto" 97
"Fernando Tatis Jr."    102
"Adley Rutschman"   72
"Yordan Alvarez"    108
"Bobby Witt Jr."    91
"Corey Seager"  94
"Will Smith"    75
"Julio Rodríguez"   88
"Shohei Ohtani" 105
"José Ramírez"  94
"Freddie Freeman"   96
"Austin Riley"  110
"Alex Bregman"  85
"Corbin Carroll"    76
"Rafael Devers" 105
"Gunnar Henderson"  81
"Mike Trout"    91
"Francisco Lindor"  83
"Vladimir Guerrero Jr." 102
"Sean Murphy"   68
"William Contreras" 78
"Kyle Tucker"   92
"Trea Turner"   83
"Bryce Harper"  90
"Marcus Semien" 90
"Dansby Swanson"    87
"Matt Olson"    108
"Cal Raleigh"   73
"Matt Chapman"  82
"Ketel Marte"   86
"Gleyber Torres"    81
"Michael Harris II" 75
"Jose Altuve"   78
"J.T. Realmuto" 70
"Manny Machado" 90
"Jonah Heim"    62
"Willy Adames"  88
/

SB(i) 'projected stolen bases for player i'
/
"Ronald Acuña Jr."  52
"Mookie Betts"  13
"Aaron Judge"   7
"Juan Soto" 10
"Fernando Tatis Jr."    32
"Adley Rutschman"   3
"Yordan Alvarez"    0
"Bobby Witt Jr."    48
"Corey Seager"  2
"Will Smith"    2
"Julio Rodríguez"   34
"Shohei Ohtani" 24
"José Ramírez"  29
"Freddie Freeman"   15
"Austin Riley"  2
"Alex Bregman"  2
"Corbin Carroll"    43
"Rafael Devers" 4
"Gunnar Henderson"  12
"Mike Trout"    3
"Francisco Lindor"  21
"Vladimir Guerrero Jr." 6
"Sean Murphy"   0
"William Contreras" 3
"Kyle Tucker"   23
"Trea Turner"   33
"Bryce Harper"  13
"Marcus Semien" 18
"Dansby Swanson"    15
"Matt Olson"    2
"Cal Raleigh"   1
"Matt Chapman"  4
"Ketel Marte"   7
"Gleyber Torres"    14
"Michael Harris II" 26
"Jose Altuve"   12
"J.T. Realmuto" 17
"Manny Machado" 7
"Jonah Heim"    2
"Willy Adames"  7
/

ADP(i) 'average draft position for player i in similar 12-team leagues'
/
"Ronald Acuña Jr." 1
"Mookie Betts"  5
"Aaron Judge"   11.4
"Juan Soto" 10.7
"Fernando Tatis Jr."    7.9
"Adley Rutschman"   53.8
"Yordan Alvarez"    16.4
"Bobby Witt Jr."    2.4
"Corey Seager"  31.7
"Will Smith"    84.3
"Julio Rodríguez"   3.1
"Shohei Ohtani" 12.7
"José Ramírez"  16.2
"Freddie Freeman"   8.7
"Austin Riley"  19.2
"Alex Bregman"  97.8
"Corbin Carroll"    6
"Rafael Devers" 24.1
"Gunnar Henderson"  32.9
"Mike Trout"    71
"Francisco Lindor"  23
"Vladimir Guerrero Jr." 29.8
"Sean Murphy"   141.4
"William Contreras" 78
"Kyle Tucker"   6.5
"Trea Turner"   12.4
"Bryce Harper"  17.7
"Marcus Semien" 31.1
"Dansby Swanson"    120.4
"Matt Olson"    17.1
"Cal Raleigh"   138.1
"Matt Chapman"  275.9
"Ketel Marte"   119.3
"Gleyber Torres"    83.3
"Michael Harris II" 28.7
"Jose Altuve"   42.9
"J.T. Realmuto" 73.3
"Manny Machado" 64.1
"Jonah Heim"    173.2
"Willy Adames"  183
/


PosC(i) 'wheather or not player i is catcher-eligible'
/
"Ronald Acuña Jr."  0
"Mookie Betts"  0
"Aaron Judge"   0
"Juan Soto" 0
"Fernando Tatis Jr."    0
"Adley Rutschman"   1
"Yordan Alvarez"    0
"Bobby Witt Jr."    0
"Corey Seager"  0
"Will Smith"    1
"Julio Rodríguez"   0
"Shohei Ohtani" 0
"José Ramírez"  0
"Freddie Freeman"   0
"Austin Riley"  0
"Alex Bregman"  0
"Corbin Carroll"    0
"Rafael Devers" 0
"Gunnar Henderson"  0
"Mike Trout"    0
"Francisco Lindor"  0
"Vladimir Guerrero Jr." 0
"Sean Murphy"   1
"William Contreras" 1
"Kyle Tucker"   0
"Trea Turner"   0
"Bryce Harper"  0
"Marcus Semien" 0
"Dansby Swanson"    0
"Matt Olson"    0
"Cal Raleigh"   1
"Matt Chapman"  0
"Ketel Marte"   0
"Gleyber Torres"    0
"Michael Harris II" 0
"Jose Altuve"   0
"J.T. Realmuto" 1
"Manny Machado" 0
"Jonah Heim"    1
"Willy Adames"  0
/
;

Scalars
DP          'draft position in round 1' /6/
Teams       'number of teams in draft'  /12/
Catcher     'minimum number of catchers on roster' /1/
HRTarget    'target minimum number of total home runs'  /100/
RTarget     'target minimum number of total runs scored'  /400/
RBITarget   'target minimum number of total runs batted in'  /250/
SBTarget    'target minimum number of total stolen bases'  /50/
;

Variables
z           'objective function variable - sum of normalized category deviation'
x(i, j)     'whether or not player i is selected in the jth round of the draft'
HR_delta    'home run deviation'
R_delta     'runs scored deviation'
RBI_delta   'runs batted in deviation'
SB_delta    'stolen bases deviation'
;

Binary variable x;
Free variables HR_delta, R_delta, RBI_delta, SB_delta;

Equations
Objective       'objective function variable - sum of normalized category deviation'
HRGoal          'home run goal'
RGoal           'runs scored goal'
RBIGoal         'runs batted in goal'
SBGoal          'stolen bases goal'
RoundMax(j)     'one pick per round'
PlayerMax(i)    'unique player can only be selected once'
ADPMax(j)       'player must be taken after their ADP'
CatcherMin      'player must be taken after their ADP'
;

Objective..         z                                                       =e=     HR_delta/HRTarget + R_delta/RTarget + RBI_delta/RBITarget + SB_delta/SBTarget;
HRGoal..            sum((i, j), HR(i) * x(i, j)) - HR_delta                 =e=     HRTarget;
RGoal..             sum((i, j), R(i) * x(i, j)) - R_delta                   =e=     RTarget;
RBIGoal..           sum((i, j), RBI(i) * x(i, j)) - RBI_delta               =e=     RBITarget;
SBGoal..            sum((i, j), SB(i) * x(i, j)) - SB_delta                 =e=     SBTarget;
RoundMax(j)..       sum(i, x(i, j))                                         =e=     1;
PlayerMax(i)..      sum(j, x(i, j))                                         =l=     1;
ADPMax(j)..         sum(i, ADP(i) * x(i, j))                                =g=     Teams * (j.pos-1) + DP;
CatcherMin..        sum((i, j), PosC(i) * x(i, j))                          =e=     Catcher;

Model fantasy_draft /all/;

Solve fantasy_draft using mip maximizing z;

Parameters
TotalHR     'total home runs'
TotalR      'total runs scored'
TotalRBI    'total runs batted in'
TotalSB     'total stolen bases'
;

TotalHR     = HRTarget  + HR_delta.l;
TotalR      = RTarget   + R_delta.l;
TotalRBI    = RBITarget + RBI_delta.l;
TotalSB     = SBTarget  + SB_delta.l;

Option x:0:1:1;
Display z.l, x.l, TotalHR, TotalR, TotalRBI, TotalSB;
