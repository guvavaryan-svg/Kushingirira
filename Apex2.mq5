//+------------------------------------------------------------------+
//| Scalper.mq5                                                      |
//| Strategy: EURUSD Scalper - Multi-Position Entry (3 Trades)       |
//| Version: 11.5 APEX SCALPER TRIPLE ENTRY (PRO RELEASE)            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

CTrade trade;

//--- STRATEGY INPUTS
input group "=== ENTRY CONTROL & TIME FILTER ==="
input bool   InstantEntryOnLoad  = false;     // SAFE DEFAULT: OFF
input int    MaxSimultaneousTrades = 3;       // Trades to open per signal (Set to 3)
input bool   UseFixedLot         = true;      
input double FixedLotSize        = 0.01;      
input bool   UseTimeFilter       = true;      // Enable Trading Hours Protection
input int    StartHour           = 2;         // Start Hour (Avoid 00:00 rollover spread)
input int    EndHour             = 20;        // End Hour (Stop opening NEW trades)

input group "=== NATIVE ECONOMIC CALENDAR NEWS FILTER ==="
input bool   UseNewsFilter       = true;      // Enable Native MT5 News Filter
input int    MinutesBeforeNews   = 30;        // Pause trading X mins BEFORE High Impact news
input int    MinutesAfterNews    = 30;        // Resume trading X mins AFTER High Impact news
input bool   CloseTradesBeforeNews = false;   // Emergency exit open trade before high news

input group "=== EURUSD HARD SL & TP CONTROL (PIPS) ==="
input bool   UseHardSLTP         = true;      
input double StopLossPips        = 20.0;      
input double TakeProfitPips      = 15.0;      

input group "=== INDICATOR SIGNAL FILTERS ==="
input int    FastMA              = 5;         
input int    SlowMA              = 20;        
input int    RSIPeriod           = 14;
input double RSIOverbought       = 55.0;      
input double RSIOversold         = 45.0;      

input group "=== PROFIT, BREAKEVEN & TRAILING ==="
input double TargetBasketProfit  = 1.50;      // Total profit for all 3 trades combined ($)
input double MaxBasketLossDollars= 6.00;      // Total stoploss cap for all 3 trades ($)
input bool   UseBasketBreakeven  = true;      // Move SL to Entry when near target
input double BasketBreakevenTrigger = 1.00;   // Trigger Breakeven at ($1.00 profit)
input bool   UseBasketTrailing   = true;      
input double BasketTrailStart    = 0.90;      
input double BasketTrailStep     = 0.30;      
input int    MaxSpreadPoints     = 30;        // Max 3.0 pips spread filter

input group "=== ADVANCED RISK PROTECTION ==="
input int    MagicNumber         = 99988; 
input double MaxTotalDrawdownPercent = 15.0;  
input bool   CloseAllOnDrawdown  = true;

// GLOBAL VARIABLES
double pip_size;
double start_balance = 0;
double highest_basket_profit = 0;
bool   is_breakeven_activated = false;
int daily_trade_count = 0;
int current_day_of_year = -1;
string bot_status_msg = "INITIALIZING";

// INDICATOR HANDLES
int handleFastMA   = INVALID_HANDLE;
int handleSlowMA   = INVALID_HANDLE;
int handleRSI      = INVALID_HANDLE;

int OnInit()
{
   SymbolSelect(_Symbol, true);

   if(_Digits == 3 || _Digits == 5)
      pip_size = _Point * 10;
   else if(_Digits == 2 || _Digits == 4)
      pip_size = _Point * 100;
   else
      pip_size = _Point;

   start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);

   handleFastMA = iMA(_Symbol, PERIOD_CURRENT, FastMA, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowMA = iMA(_Symbol, PERIOD_CURRENT, SlowMA, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI    = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);

   if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("Error creating indicator handles.");
      return(INIT_FAILED);
   }

   CreateDashboardUI();

   if(InstantEntryOnLoad && CountOurPositions() == 0)
   {
      ExecuteInstantTrades();
   }

   Print("APEX SCALPER V11.5 (TRIPLE ENTRY ENGINE) LOADED.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleFastMA);
   IndicatorRelease(handleSlowMA);
   IndicatorRelease(handleRSI);
   ObjectsDeleteAll(0, "Apex_Dash_");
}

void CreateDashboardLabel(string name, string text, int x, int y, color clr, int font_size = 9, bool is_bold = false)
{
   string obj_name = "Apex_Dash_" + name;
   if(ObjectFind(0, obj_name) < 0)
   {
      ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj_name, OBJPROP_CORNER, 1);
      ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, 1);
      ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, obj_name, OBJPROP_FONT, "Trebuchet MS");
   }
   ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, font_size);
}

void CreateDashboardUI()
{
   string bg_name = "Apex_Dash_BG";
   if(ObjectFind(0, bg_name) < 0)
   {
      ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg_name, OBJPROP_CORNER, 1);
      ObjectSetInteger(0, bg_name, OBJPROP_ANCHOR, 1);
      ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, 10);
      ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, 240);
      ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, 210);
      ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, C'20,24,32');
      ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg_name, OBJPROP_COLOR, C'50,60,75');
   }
}

void UpdateDashboard()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double open_profit = GetTotalBasketProfit();
   string acc_currency = AccountInfoString(ACCOUNT_CURRENCY); // Gadziriswa pano

   color profit_clr = (open_profit >= 0) ? clrLimeGreen : clrTomato;
   string profit_str = (open_profit >= 0) ? "+" + DoubleToString(open_profit, 2) : DoubleToString(open_profit, 2);

   CreateDashboardLabel("Title", "--- APEX SCALPER V11.5 ---", 25, 20, clrGold, 10, true);
   CreateDashboardLabel("Balance", "Balance: " + DoubleToString(balance, 2) + " " + acc_currency, 25, 42, clrWhite);
   CreateDashboardLabel("Equity", "Equity: " + DoubleToString(equity, 2) + " " + acc_currency, 25, 60, clrWhite);
   CreateDashboardLabel("Profit", "Floating P/L: " + profit_str, 25, 80, profit_clr, 9, true);
   CreateDashboardLabel("OpenOrders", "Open Positions: " + IntegerToString(CountOurPositions()), 25, 100, clrDeepSkyBlue);
   CreateDashboardLabel("DailyTrades", "Daily Trades: " + IntegerToString(daily_trade_count), 25, 120, clrCyan);

   double total_drawdown = (start_balance > 0) ? (start_balance - equity) / start_balance * 100.0 : 0;
   if(total_drawdown < 0) total_drawdown = 0;
   CreateDashboardLabel("Drawdown", "Drawdown: " + DoubleToString(total_drawdown, 2) + "%", 25, 140, clrOrange);
   
   CreateDashboardLabel("Status", "Status: " + bot_status_msg, 25, 165, clrLime, 9, true);
}

double CleanAndNormalizeLot(double raw_lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(step <= 0) step = 0.01;
   double normalized = MathFloor(raw_lot / step) * step;

   int digits = (step == 0.01) ? 2 : ((step == 0.1) ? 1 : 3);
   normalized = NormalizeDouble(normalized, digits);

   if(normalized < min_lot) normalized = min_lot;
   if(normalized > max_lot) normalized = max_lot;

   return normalized;
}

int CountOurPositions(int type = -1)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      string sym = PositionGetSymbol(i);
      if(sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         if(type == -1 || PositionGetInteger(POSITION_TYPE) == type) count++;
      }
   }
   return count;
}

double GetTotalBasketProfit()
{
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      string sym = PositionGetSymbol(i);
      if(sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }
   return profit;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      string sym = PositionGetSymbol(i);
      if(sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         trade.PositionClose(ticket);
      }
   }
   highest_basket_profit = 0;
   is_breakeven_activated = false;
}

bool IsHighImpactNewsNear()
{
   if(!UseNewsFilter) return false;

   datetime now = TimeCurrent();
   datetime from_time = now - (MinutesAfterNews * 60);
   datetime to_time   = now + (MinutesBeforeNews * 60);

   MqlCalendarValue values[];
   
   int count = CalendarValueHistory(values, from_time, to_time, NULL, NULL);
   if(count <= 0) return false;

   for(int i = 0; i < count; i++)
   {
      MqlCalendarEvent event;
      if(CalendarEventById(values[i].event_id, event))
      {
         if(event.currency == "EUR" || event.currency == "USD")
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               bot_status_msg = "PAUSED (HIGH IMPACT NEWS)";

               if(CloseTradesBeforeNews && CountOurPositions() > 0)
               {
                  CloseAllPositions();
                  bot_status_msg = "NEWS EMERGENCY CLOSE";
               }
               return true;
            }
         }
      }
   }
   return false;
}

bool CheckTradingHours()
{
   if(!UseTimeFilter) return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.hour < StartHour || dt.hour >= EndHour)
   {
      bot_status_msg = "PAUSED (OUTSIDE HOURS)";
      return false;
   }
   return true;
}

bool CheckSpread()
{ 
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread_points = (ask - bid) / _Point; 
   if(spread_points > MaxSpreadPoints)
   { 
      bot_status_msg = "PAUSED (HIGH SPREAD)";
      return false;
   } 
   return true; 
}

void ApplyBasketBreakeven()
{
   if(!UseBasketBreakeven || is_breakeven_activated || CountOurPositions() == 0) return;

   if(GetTotalBasketProfit() >= BasketBreakevenTrigger)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         string sym = PositionGetSymbol(i);
         if(sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double open_p = PositionGetDouble(POSITION_PRICE_OPEN);
            long type   = PositionGetInteger(POSITION_TYPE);
            
            double be_sl = (type == POSITION_TYPE_BUY) ? open_p + (5.0 * pip_size) : open_p - (5.0 * pip_size);
            be_sl = NormalizeDouble(be_sl, _Digits);
            
            double current_tp = PositionGetDouble(POSITION_TP);
            trade.PositionModify(ticket, be_sl, current_tp);
         }
      }
      is_breakeven_activated = true;
      bot_status_msg = "BREAKEVEN SET (+5 Pips)";
   }
}

void ExecuteInstantTrades()
{
   double lot = CleanAndNormalizeLot(FixedLotSize);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = UseHardSLTP ? NormalizeDouble(ask - (StopLossPips * pip_size), _Digits) : 0;
   double tp = UseHardSLTP ? NormalizeDouble(ask + (TakeProfitPips * pip_size), _Digits) : 0;
   
   for(int i = 0; i < MaxSimultaneousTrades; i++)
   {
      if(trade.Buy(lot, _Symbol, ask, sl, tp, "Apex_Instant_Buy_" + IntegerToString(i + 1)))
      {
         daily_trade_count++;
      }
   }
   bot_status_msg = "INSTANT 3x BUY EXECUTED";
}

void ManageBasketCloseAndTrailing()
{
   double total_profit = GetTotalBasketProfit();

   if(CountOurPositions() > 0 && total_profit >= TargetBasketProfit)
   {
      CloseAllPositions();
      bot_status_msg = "TARGET PROFIT CLOSED";
      return;
   }

   if(CountOurPositions() > 0 && total_profit <= -MathAbs(MaxBasketLossDollars))
   {
      CloseAllPositions();
      bot_status_msg = "STOPLOSS HIT";
      return;
   }

   ApplyBasketBreakeven();

   if(UseBasketTrailing && CountOurPositions() > 0)
   {
      if(total_profit >= BasketTrailStart)
      {
         if(total_profit > highest_basket_profit) highest_basket_profit = total_profit;

         if(highest_basket_profit - total_profit >= BasketTrailStep)
         {
            CloseAllPositions();
            bot_status_msg = "TRAIL PROFIT CLOSED";
            return;
         }
      }
   }
}

void CheckEquityProtection()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown = (start_balance > 0) ? (start_balance - equity) / start_balance * 100.0 : 0;

   if(CloseAllOnDrawdown && drawdown >= MaxTotalDrawdownPercent)
   {
      CloseAllPositions();
      bot_status_msg = "EMERGENCY DRAWDOWN HALT";
   }
}

bool GetEntrySignal(int &signal)
{
   signal = 0;
   double fastMA[], slowMA[], rsi[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleFastMA, 0, 1, 2, fastMA) < 2 || 
      CopyBuffer(handleSlowMA, 0, 1, 2, slowMA) < 2 ||
      CopyBuffer(handleRSI, 0, 1, 1, rsi) < 1) return false;

   if(fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0] && rsi[0] < RSIOversold) signal = 1;
   if(fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0] && rsi[0] > RSIOverbought) signal = -1;

   return (signal != 0);
}

void ResetDailyCounterIfNeeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != current_day_of_year)
   {
      current_day_of_year = dt.day_of_year;
      daily_trade_count = 0;
   }
}

void OpenInitialTrade(int signal)
{
   if(CountOurPositions() > 0) return;

   double lot = CleanAndNormalizeLot(FixedLotSize);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(signal == 1)
   {
      double sl = UseHardSLTP ? NormalizeDouble(ask - (StopLossPips * pip_size), _Digits) : 0;
      double tp = UseHardSLTP ? NormalizeDouble(ask + (TakeProfitPips * pip_size), _Digits) : 0;

      for(int i = 0; i < MaxSimultaneousTrades; i++)
      {
         if(trade.Buy(lot, _Symbol, ask, sl, tp, "Apex_Buy_" + IntegerToString(i + 1)))
         {
            daily_trade_count++;
         }
      }
      bot_status_msg = "3x BUY TRADES OPENED";
   }
   else if(signal == -1)
   {
      double sl = UseHardSLTP ? NormalizeDouble(bid + (StopLossPips * pip_size), _Digits) : 0;
      double tp = UseHardSLTP ? NormalizeDouble(bid - (TakeProfitPips * pip_size), _Digits) : 0;

      for(int i = 0; i < MaxSimultaneousTrades; i++)
      {
         if(trade.Sell(lot, _Symbol, bid, sl, tp, "Apex_Sell_" + IntegerToString(i + 1)))
         {
            daily_trade_count++;
         }
      }
      bot_status_msg = "3x SELL TRADES OPENED";
   }
}

//+------------------------------------------------------------------+
//| Main OnTick Execution Loop                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyCounterIfNeeded();

   // 1. Circuit Breakers: Check High Impact News AND Trading Session Hours First
   if(IsHighImpactNewsNear() || !CheckTradingHours()) 
   { 
      UpdateDashboard(); 
      return; 
   }

   // 2. Spread Check Filter
   if(!CheckSpread()) 
   { 
      UpdateDashboard(); 
      return; 
   }

   // 3. Risk Protection & Trailing Logic
   CheckEquityProtection();
   ManageBasketCloseAndTrailing();

   // 4. Check Signal to Open 3 Trades simultaneously
   int signal;
   if(GetEntrySignal(signal)) OpenInitialTrade(signal);

   if(CountOurPositions() == 0) bot_status_msg = "ACTIVE (SCANNING)";
   UpdateDashboard();
}
