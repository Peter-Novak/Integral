/*
****************************************************************************************************************************************************************************************
*                                                                                                                                                                                      *
* Integral.mq4, verzija: 1, avgust 2016                                                                                                                                                *     *
*                                                                                                                                                                                      *
* Copyright Peter Novak ml., M.Sc.                                                                                                                                                     *
****************************************************************************************************************************************************************************************
*/

#property copyright "Peter Novak ml., M.Sc."
#property link "http://www.marlin.si"

// Vhodni parametri --------------------------------------------------------------------------------------------------------------------------------------------------------------------
extern double L; // Velikost pozicij v lotih;
extern double p; // Profitni cilj;
extern double r; // Razdalja za samodejno odpiranje pozicije - kadar cena poskoči za več kot r točk se samodejno odpre pozicija;
extern odmikSL;  // Odmik od cene odprtja pri kateri ročno zapremo pozicijo. Velja za pozicije pri katerih SL ni bilo možno nastaviti zaradi premajhne razdalje;


// Globalne konstante ------------------------------------------------------------------------------------------------------------------------------------------------------------------
#define MAX_POZ     9999 // največje možno število odprtih pozicij;
#define USPEH      -4   // oznaka za povratno vrednost pri uspešno izvedenem klicu funkcije;
#define NAPAKA     -5   // oznaka za povratno vrednost pri neuspešno izvedenem klicu funkcije;
#define ZE_OBSTAJA -6   // pri dodajanju pozicije v vrsto se je izkazalo, da je pozicija že v vrsti;
#define S0          1   // oznaka za stanje S0 - Čakaj na zagon;
#define S1          2   // oznaka za stanje S1 - Odpri pozicijo;
#define S2          3   // oznaka za stanje S2 - Upravljaj pozicije;
#define S3          4   // oznaka za stanje S3 - Zaključek;



// Globalne spremenljivke --------------------------------------------------------------------------------------------------------------------------------------------------------------
int    pozicije [MAX_POZ];  // Enolične oznake vseh odprtih pozicij;
int    kazalecPozicije;     // Indeks naslednjega prostega mesta v polju pozicije;
int    kazalecslPozicije;   // Indeks, ki kaže na naslednjo pozicijo, ki je kandidat da se ji SL postavi na BE;
double izkupicek;           // Izkupiček trenutne iteracije algoritma (izkupiček odprtih in zaprtih pozicij)
int    kslVrsta;            // Kazalec na naslednje prosto mesto v polju slVrsta
double maxIzpostavljenost;  // Največja izguba algoritma (minimum od izkupicek);
int    slVrsta   [MAX_POZ]; // Hrani id-je vseh pozicij, pri katerih postavljanje stop loss ukazov ni bilo uspešno
int    stanje;              // Trenutno stanje algoritma;
int verzija = 1;            // Trenutna verzija algoritma;



/*
****************************************************************************************************************************************************************************************
*                                                                                                                                                                                      *
* GLAVNI PROGRAM in obvezne funkcije: init, deinit, start                                                                                                                              *
*                                                                                                                                                                                      *
****************************************************************************************************************************************************************************************
*/



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: deinit  
----------------
(o) Funkcionalnost: Sistem jo pokliče ob zaustavitvi. M5 je ne uporablja
(o) Zaloga vrednosti: USPEH (vedno uspe)
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/   
int deinit()
{
  return( USPEH );
} // deinit 



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: init  
--------------
(o) Funkcionalnost: Sistem jo pokliče ob zagonu. V njej izvedemo naslednje:
  (-) izpišemo pozdravno sporočilo
  (-) ponastavimo vse ključne podatkovne strukture algoritma na začetne vrednosti
(o) Zaloga vrednosti: USPEH, NAPAKA
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int init()
{
  Print( "****************************************************************************************************************" );
  Print( "Dober dan. Tukaj Integral, verzija ", verzija, "." );
  Print( "****************************************************************************************************************" );
  
  kazalecPozicije    = 0;
  kazalecslPozicije  = 0;
  kslVrsta           = 0;
  izkupicek          = 0;
  maxIzpostavljenost = 0;
  stanje             = S0;
  
  return( USPEH );
} // init



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: start  
---------------
(o) Funkcionalnost: Glavna funkcija, ki upravlja celoten algoritem - sistem jo pokliče ob vsakem ticku. 
(o) Zaloga vrednosti: USPEH (funkcija vedno uspe)
(o) Vhodni parametri: /
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int start()
{
  int trenutnoStanje; // zabeležimo za ugotavljanje spremebe stanja
 
  trenutnoStanje = stanje;
  switch( stanje )
  {
    case S0: stanje = S0CakanjeNaZagon();    break;
    case S1: stanje = S1OdpriPozicijo();     break;
    case S2: stanje = S2UpravljajPozicije(); break;
    case S3: stanje = S3Zakljucek();         break;
    default: Print( "Integral V", verzija, ":start:OPOZORILO: Stanje ", stanje, " ni veljavno stanje - preveri pravilnost delovanja algoritma." );
  }
  // če je prišlo do prehoda med stanji izpišemo obvestilo
  if( trenutnoStanje != stanje ) { Print( "Prehod: ", ImeStanja( trenutnoStanje ), " ===========>>>>> ", ImeStanja( stanje ) ); }

  // če se je poslabšala izpostavljenost, to zabeležimo
  if( maxIzpostavljenost > izkupicek ) { maxIzpostavljenost = izkupicek; Print( "Nova največja izpostavljenost: ", DoubleToString( maxIzpostavljenost, 5 ) ); }
    
  // osveževanje ključnih kazalnikov delovanja algoritma na zaslonu
  Comment( "Izkupiček iteracije: ",      DoubleToString( izkupicek,  5 ), " \n",
           "Razdalja do cilja: ",        DoubleToString( p - skupniIzkupicek, 5 ), " \n",
           "Največja izpostavljenost: ", DoubleToString( maxIzpostavljenost,  5 ) );
  
  // če vrsta pozicij za ponastavljanje stop loss-ov ni prazna, poskusimo ponastaviti stop-loss-e
  if( kslVrsta > 0 ) { PreveriSL(); }
  return( USPEH );
} // start



/*--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA DKA: S0CakanjeNaZagon() 
----------------------------
V to stanje vstopimo po zaključeni inicializaciji. V tem stanju čakamo, da se bo začela nova sveča in ko se to zgodi:
(1) dodamo novo pozicijo v ustrezni smeri;
(2) preverimo ali imamo odprtih več kot 10 pozicij in če da, potem dodamo ustrezne pozicije v vrsto za postavitev SL;
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------*/
int S0CakanjeNaZagon()
{
  if( OdprtaJeNovaSveca() == true ) 
  { 
    if( pozicije[ ka
    cz = cenaObZagonu; Print( "M5V", verzija, ":[", stevilkaIteracije, "]:", ":S0CakanjeNaZagon: Začetna cena [cz] = ", DoubleToString( cz, 5 ) ); return( S1 ); }
  if( ( ( cenaObZagonu >= cz ) && ( Bid <= cz ) ) || ( ( cenaObZagonu <= cz ) && ( Bid >= cz ) ) ) { return( S1 ); }
  else                                                                                             { return( S0 ); }
} // S0CakanjeNaZagon
