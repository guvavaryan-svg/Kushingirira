//+------------------------------------------------------------------+
//| Never give Up.mq5                                               |
//| Strategy: Commercial Multi-Grid Recovery & Instant Scalper Engine|
//| Version: 9.0 COMMERCIAL FULL EDITION                            |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

CTrade trade;

//--- STRATEGY INPUTS
input group "=== INSTANT EXECUTION & ENTRY ==="
input bool   InstantEntryOnLoad  = true;      // Open market trade immediately when attached to chart
input bool   UseFixedLot         = true;      
input double FixedLotSize        = 0.01;      
input double RiskPercent         = 1.0;       

input group "=== COMMERCIAL GRID RECOVERY ==="
input bool   UseGridSystem       = true;      // Continuous Grid Trading
input double GridStepPips        = 25.0;      // Distance between grid recovery orders
input int    MaxGridOrders       = 6;         // Maximum grid depth
input double GridLotMultiplier   = 1.35;     // Recovery Lot Multiplier

input group "=== FAST INDICATOR SIGNALS ==="
input int    FastMA              = 5;         
input int    SlowMA              = 20;        
input int    RSIPeriod           = 14;

input group "=== BASKET PROFIT & TRAILING ==="
input double TargetBasketProfit  = 3.0;       // Close ALL open trades when Total Profit hits this ($)
input bool   UseBasketTrailing   = true;      // Trailing stop on total floating profit
input double BasketTrailStart    = 2.0;       // Start profit trailing at ($)
input double BasketTrailStep     = 0.5;       // Lock step profit ($)
input int    MaxSpreadPoints     = 1000;      // High spread protection for Deriv/Gold

input group "=== ADVANCED RISK PROTECTION ==="
input int    MagicNumber         = 99988; 
input double MaxTotalDrawdownPercent = 15.0;  // Auto-close all trades if account drawdown hits %
input bool   CloseAllOnDrawdown  = true;

// GLOBAL VARIABLES
double pip_size;
double start_balance = 0;
double highest_basket_profit = 0;
int daily_trade_count = 0;
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

   // Instant entry trigger when EA is loaded on chart
   if(InstantEntryOnLoad && CountOurPositions() == 0)
   {
      ExecuteInstantTrade();
   }

   Print("NEVER GIVE UP V9.0 COMMERCIAL EDITION LOADED SUCCESSFULLY.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleFastMA);
   IndicatorRelease(handleSlowMA);
   IndicatorRelease(handleRSI);
   ObjectsDeleteAll(0, "NGU_Dash_");
}

void CreateDashboardLabel(string name, string text, int x, int y, color clr, int font_size = 9, bool is_bold = false)
{
   string obj_name = "NGU_Dash_" + name;
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
   string bg_name = "NGU_Dash_BG";
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

   color profit_clr = (open_profit >= 0) ? clrLimeGreen : clrTomato;
   string profit_str = (open_profit >= 0) ? "+" + DoubleToString(open_profit, 2) : DoubleToString(open_profit, 2);

   CreateDashboardLabel("Title", "--- COMMERCIAL PRO V9.0 ---", 25, 20, clrGold, 10, true);
   CreateDashboardLabel("Balance", "Balance: " + DoubleToString(balance, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), 25, 42, clrWhite);
   CreateDashboardLabel("Equity", "Equity: " + DoubleToString(equity, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), 25, 60, clrWhite);
   CreateDashboardLabel("Profit", "Floating P/L: " + profit_str, 25, 80, profit_clr, 9, true);
   CreateDashboardLabel("OpenOrders", "Grid Orders: " + IntegerToString(CountOurPositions()), 25, 100, clrDeepSkyBlue);
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

void ExecuteInstantTrade()
{
   double lot = CleanAndNormalizeLot(FixedLotSize);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(trade.Buy(lot, _Symbol, ask, 0, 0, "Commercial_Instant_Buy"))
   {
      daily_trade_count++;
      bot_status_msg = "INSTANT BUY EXECUTED";
   }
}

void ManageBasketCloseAndTrailing()
{
   double total_profit = GetTotalBasketProfit();

   if(CountOurPositions() > 0 && total_profit >= TargetBasketProfit)
   {
      CloseAllPositions();
      bot_status_msg = "BASKET TARGET CLOSED";
      return;
   }

   if(UseBasketTrailing && CountOurPositions() > 0)
   {
      if(total_profit >= BasketTrailStart)
      {
         if(total_profit > highest_basket_profit) highest_basket_profit = total_profit;

         if(highest_basket_profit - total_profit >= BasketTrailStep)
         {
            CloseAllPositions();
            bot_status_msg = "BASKET TRAIL CLOSED";
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

void ProcessGridEntries()
{
   if(!UseGridSystem || CountOurPositions() == 0) return;

   int buy_count = CountOurPositions(POSITION_TYPE_BUY);
   int sell_count = CountOurPositions(POSITION_TYPE_SELL);

   double last_price = 0;
   double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buy_count > 0 && buy_count < MaxGridOrders)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            last_price = PositionGetDouble(POSITION_PRICE_OPEN);
            break;
         }
      }

      if(current_ask <= last_price - (GridStepPips * pip_size))
      {
         double next_lot = CleanAndNormalizeLot(FixedLotSize * MathPow(GridLotMultiplier, buy_count));
         if(trade.Buy(next_lot, _Symbol, current_ask, 0, 0, "Grid_Buy_Layer_" + IntegerToString(buy_count)))
         {
            daily_trade_count++;
            bot_status_msg = "GRID BUY LAYER OPENED";
         }
      }
   }

   if(sell_count > 0 && sell_count < MaxGridOrders)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            last_price = PositionGetDouble(POSITION_PRICE_OPEN);
            break;
         }
      }

      if(current_bid >= last_price + (GridStepPips * pip_size))
      {
         double next_lot = CleanAndNormalizeLot(FixedLotSize * MathPow(GridLotMultiplier, sell_count));
         if(trade.Sell(next_lot, _Symbol, current_bid, 0, 0, "Grid_Sell_Layer_" + IntegerToString(sell_count)))
         {
            daily_trade_count++;
            bot_status_msg = "GRID SELL LAYER OPENED";
         }
      }
   }
}

bool GetEntrySignal(int &signal)
{
   signal = 0;
   double fastMA[], slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

   if(CopyBuffer(handleFastMA, 0, 1, 2, fastMA) < 2 || CopyBuffer(handleSlowMA, 0, 1, 2, slowMA) < 2) return false;

   if(fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0]) signal = 1;
   if(fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0]) signal = -1;

   return (signal != 0);
}

void OpenInitialTrade(int signal)
{
   if(CountOurPositions() > 0) return;

   double lot = CleanAndNormalizeLot(FixedLotSize);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(signal == 1)
   {
      if(trade.Buy(lot, _Symbol, ask, 0, 0, "Commercial_Buy"))
      {
         daily_trade_count++;
         bot_status_msg = "BUY ENTRY OPENED";
      }
   }
   else if(signal == -1)
   {
      if(trade.Sell(lot, _Symbol, bid, 0, 0, "Commercial_Sell"))
      {
         daily_trade_count++;
         bot_status_msg = "SELL ENTRY OPENED";
      }
   }
}

void OnTick()
{
   if(!CheckSpread()) { UpdateDashboard(); return; }

   CheckEquityProtection();
   ManageBasketCloseAndTrailing();
   ProcessGridEntries();

   int signal;
   if(GetEntrySignal(signal)) OpenInitialTrade(signal);

   if(CountOurPositions() == 0) bot_status_msg = "ACTIVE (SCANNING)";
   UpdateDashboard();
}
