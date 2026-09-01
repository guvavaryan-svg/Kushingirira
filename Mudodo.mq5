//+------------------------------------------------------------------+
//| Never give Up.mq5                                               |
//| Strategy: EMA + RSI + DIP/RIP + MARTINGALE (FAST ENTRY VERSION) |
//| Version: 6.7 Fast Signals                                        |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

CTrade trade;

//--- STRATEGY INPUTS
input bool   UseFixedLot         = true;      // Set to TRUE for fixed lot size
input double FixedLotSize        = 0.01;      // Manual Lot size if UseFixedLot = true
input double RiskPercent         = 1.0;       // Risk per trade in %
input int    FastMA              = 3;         // Reduced for faster crossover
input int    SlowMA              = 15;        // Reduced for faster crossover
input int    RSIPeriod           = 14;

//--- PARABOLIC SAR & MACD INPUTS (DISABLED FOR FAST ENTRY)
input bool   UseSARFilter        = false;     // Set to false for instant trades
input double SARStep             = 0.02;      
input double SARMaximum          = 0.2;       
input bool   UseMACDFilter       = false;     // Set to false for instant trades
input int    MACDFast            = 12;        
input int    MACDSlow            = 26;        
input int    MACDSignal          = 9;         

input double StopLossPips        = 20.0;      // SL in Pips
input double TakeProfitPips      = 40.0;      // TP in Pips
input double BreakEven           = 15.0;      // Break Even trigger in Pips
input double TrailStart          = 20.0;      // Trailing Stop start in Pips
input double TrailStep           = 5.0;       // Trailing Stop step in Pips
input int    MaxSpreadPoints     = 150;       // Spread limit

//--- PARTIAL TAKE PROFIT
input bool   UsePartialClose     = true;      
input double PartialTPTriggerPips= 25.0;      

//--- MULTI-TIMEFRAME TREND FILTER
input bool   UseMTFTrendFilter   = false;     
input ENUM_TIMEFRAMES HTF_Period = PERIOD_M1; 

//--- DIP/RIP INPUTS
input bool   UseDipRip           = true;
input double DipMultiplier      = 1.5;
input double RipMultiplier      = 1.5;
input int    RSIDip              = 30;
input int    RSIRip              = 70;

//--- MARTINGALE INPUTS
input bool   UseMartingale       = true;
input double MartingaleMultiplier= 1.3;      
input int    MaxMartingaleSteps  = 3;

//--- SIDEWAYS FILTER & EMERGENCY EXIT
input bool   UseSidewaysFilter   = false;     
input bool   EmergencyExitSideways = false;   
input int    ADXPeriod           = 14;
input double ADXThreshold        = 20.0;
input int    ATRPeriod           = 14;
input double MinATR              = 0.00005;      

//--- DAY FILTER INPUTS
input bool   TradeSunday         = true;      
input bool   TradeMonday         = true;      
input bool   TradeTuesday        = true;      
input bool   TradeWednesday      = true;      
input bool   TradeThursday       = true;      
input bool   TradeFriday         = true;      
input bool   TradeSaturday       = true;      

//--- ADVANCED RISK & TRADING FILTERS
input int    MaxDailyTrades      = 10;        
input bool   CloseFridayWeekend  = true;      
input int    FridayCloseHour     = 21;        

//--- PROTECTION & MANAGEMENT INPUTS
input int    MagicNumber         = 12347; 
input bool   TradeOnlyOne        = true;
input double MaxDailyLossPercent = 5.0;       
input double MaxTotalDrawdownPercent = 8.0;   
input bool   CloseAllOnHalt      = true;
input bool   UseTradingHours     = false;     
input int    StartHour           = 0;             
input int    EndHour             = 24;              
input int    CooldownMinutes     = 0;         // Set to 0 for no cooldown

//--- CALENDAR NEWS FILTER (DISABLED FOR FAST ENTRY)
input bool   UseNewsFilter       = false;     // Disabled news filter to prevent pauses
input int    MinutesBeforeNews   = 30;        
input int    MinutesAfterNews    = 30;        
input bool   FilterHighImpact    = true;      
input bool   FilterMediumImpact  = false;     
input bool   FilterLowImpact     = false;     

// GLOBAL VARIABLES
double pip_size;
double equity_peak = 0;
double start_balance = 0;
datetime last_trade_time = 0;
int last_day = -1;
int martingale_step = 0; 
int daily_trade_count = 0;
string bot_status_msg = "INITIALIZING";

// INDICATOR HANDLES
int handleFastMA   = INVALID_HANDLE;
int handleSlowMA   = INVALID_HANDLE;
int handleRSI      = INVALID_HANDLE;
int handleATR      = INVALID_HANDLE;
int handleADX      = INVALID_HANDLE;

int OnInit()
{
   SymbolSelect(_Symbol, true);

   if(_Digits == 3 || _Digits == 5)
      pip_size = _Point * 10;
   else
      pip_size = _Point;

   equity_peak = AccountInfoDouble(ACCOUNT_EQUITY);
   start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   last_day = dt.day;
   
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   handleFastMA = iMA(_Symbol, PERIOD_CURRENT, FastMA, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowMA = iMA(_Symbol, PERIOD_CURRENT, SlowMA, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI    = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
   handleATR    = iATR(_Symbol, PERIOD_CURRENT, ATRPeriod);
   handleADX    = iADX(_Symbol, PERIOD_CURRENT, ADXPeriod);

   if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE || 
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE || 
      handleADX == INVALID_HANDLE)
   {
      Print("Error creating indicator handles.");
      return(INIT_FAILED);
   }

   CheckLastClosedTradeResult();
   CreateDashboardUI();

   Print("NEVER GIVE UP V6.7 FAST - Symbol: ", _Symbol, " | Magic: ", MagicNumber);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleFastMA);
   IndicatorRelease(handleSlowMA);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
   IndicatorRelease(handleADX);
   
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
   double today_profit = equity - start_balance;

   color profit_clr = (today_profit >= 0) ? clrLimeGreen : clrTomato;
   string profit_str = (today_profit >= 0) ? "+" + DoubleToString(today_profit, 2) : DoubleToString(today_profit, 2);

   CreateDashboardLabel("Title", "--- NEVER GIVE UP EA V6.7 ---", 25, 20, clrGold, 10, true);
   CreateDashboardLabel("Balance", "Balance: " + DoubleToString(balance, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), 25, 42, clrWhite);
   CreateDashboardLabel("Equity", "Equity: " + DoubleToString(equity, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), 25, 60, clrWhite);
   CreateDashboardLabel("Profit", "Today Profit: " + profit_str, 25, 80, profit_clr, 9, true);
   CreateDashboardLabel("Martingale", "Martingale Step: " + IntegerToString(martingale_step) + " / " + IntegerToString(MaxMartingaleSteps), 25, 100, clrDeepSkyBlue);
   CreateDashboardLabel("DailyTrades", "Daily Trades: " + IntegerToString(daily_trade_count) + " / " + ((MaxDailyTrades > 0) ? IntegerToString(MaxDailyTrades) : "INF"), 25, 120, clrCyan);

   double daily_loss = (start_balance > 0) ? (start_balance - equity) / start_balance * 100.0 : 0;
   if(daily_loss < 0) daily_loss = 0;
   CreateDashboardLabel("DailyLoss", "Daily Loss: " + DoubleToString(daily_loss, 2) + "% / " + DoubleToString(MaxDailyLossPercent, 1) + "%", 25, 140, clrOrange);
   
   color status_color = clrLime;
   if(StringFind(bot_status_msg, "PAUSED") >= 0 || StringFind(bot_status_msg, "COOLDOWN") >= 0) status_color = clrOrange;
   if(StringFind(bot_status_msg, "HALTED") >= 0 || StringFind(bot_status_msg, "EXIT") >= 0) status_color = clrRed;

   CreateDashboardLabel("Status", "Status: " + bot_status_msg, 25, 165, status_color, 9, true);
}

double CleanAndNormalizeLot(double raw_lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(step <= 0) step = 0.01;
   double normalized = MathFloor(raw_lot / step) * step;

   int digits = 0;
   if(step == 0.01) digits = 2;
   else if(step == 0.1) digits = 1;
   else if(step == 0.001) digits = 3;

   normalized = NormalizeDouble(normalized, digits);

   if(normalized < min_lot) normalized = min_lot;
   if(normalized > max_lot) normalized = max_lot;

   return normalized;
}

void CheckLastClosedTradeResult()
{
   if(!UseMartingale) return;

   HistorySelect(0, TimeCurrent());
   int total_deals = HistoryDealsTotal();

   for(int i = total_deals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);

         if(symbol == _Symbol && magic == MagicNumber && entry == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            if(profit < 0)
            {
               if(martingale_step < MaxMartingaleSteps)
                  martingale_step++;
            }
            else if(profit > 0)
            {
               martingale_step = 0;
            }
            break; 
         }
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      CheckLastClosedTradeResult();
      UpdateDashboard();
   }
}

int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      string sym = PositionGetSymbol(i);
      if(sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      string sym = PositionGetSymbol(i);
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      if(ticket > 0 && sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         trade.PositionClose(ticket);
      }
   }
}

bool CheckFridayFilter()
{
   if(!CloseFridayWeekend) return true;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   if(dt.day_of_week == 5 && dt.hour >= FridayCloseHour)
   {
      bot_status_msg = "PAUSED (WEEKEND CLOSE)";
      if(CountOurPositions() > 0)
      {
         CloseAllPositions();
         Print("Friday Weekend Close Triggered. Positions Closed.");
      }
      return false;
   }
   return true;
}

bool IsMarketTrending()
{
   if(!UseSidewaysFilter) return true;
   
   double adx[];
   double atr[];
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   
   if(CopyBuffer(handleADX, 0, 1, 1, adx) <= 0 || CopyBuffer(handleATR, 0, 1, 1, atr) <= 0)
      return false;
   
   if(adx[0] < ADXThreshold || atr[0] < MinATR)
   {
      bot_status_msg = "SIDEWAYS DETECTED";
      if(EmergencyExitSideways && CountOurPositions() > 0)
      {
         CloseAllPositions();
         bot_status_msg = "EMERGENCY EXIT (SIDEWAYS)";
      }
      return false;
   }
   return true;
}

bool CheckAllowedDays()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   bool allowed = false;
   if(dt.day_of_week == 0 && TradeSunday) allowed = true;
   if(dt.day_of_week == 1 && TradeMonday) allowed = true;
   if(dt.day_of_week == 2 && TradeTuesday) allowed = true;
   if(dt.day_of_week == 3 && TradeWednesday) allowed = true;
   if(dt.day_of_week == 4 && TradeThursday) allowed = true;
   if(dt.day_of_week == 5 && TradeFriday) allowed = true;
   if(dt.day_of_week == 6 && TradeSaturday) allowed = true;
   
   if(!allowed)
      bot_status_msg = "PAUSED (OFF-DAY)";
      
   return allowed;
}

bool EquityProtector()
{
   MqlDateTime dt; 
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day != last_day)
   {
      start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      equity_peak = AccountInfoDouble(ACCOUNT_EQUITY);
      last_day = dt.day;
      martingale_step = 0; 
      daily_trade_count = 0;
      Print("New Day Reset. Balance: ", start_balance);
   }
   
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(current_equity > equity_peak) equity_peak = current_equity;
   
   double daily_loss = (start_balance > 0) ? (start_balance - current_balance) / start_balance * 100.0 : 0;
   double drawdown = (equity_peak > 0) ? (equity_peak - current_equity) / equity_peak * 100.0 : 0;
   
   if(daily_loss >= MaxDailyLossPercent || drawdown >= MaxTotalDrawdownPercent)
   {
      bot_status_msg = "HALTED (MAX DD/LOSS)";
      if(CloseAllOnHalt) CloseAllPositions();
      return false;
   }
   
   if(MaxDailyTrades > 0 && daily_trade_count >= MaxDailyTrades)
   {
      bot_status_msg = "PAUSED (MAX DAILY TRADES)";
      return false;
   }

   bot_status_msg = "ACTIVE";
   return true;
}

bool CheckTradingHours()
{ 
   if(!UseTradingHours) return true; 
   MqlDateTime dt; 
   TimeToStruct(TimeCurrent(), dt); 
   bool active = (dt.hour >= StartHour && dt.hour < EndHour);
   if(!active) bot_status_msg = "PAUSED (HOURS)";
   return active; 
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

double CalculateLotSize(double sl_pips)
{
   double lot = FixedLotSize;
   
   if(!UseFixedLot)
   {
      double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tick_size > 0 && tick_value > 0)
      {
         double sl_in_price = sl_pips * pip_size;
         lot = risk_amount / (sl_in_price / tick_size * tick_value);
      }
   }

   if(UseMartingale && martingale_step > 0)
      lot = lot * MathPow(MartingaleMultiplier, martingale_step);

   return CleanAndNormalizeLot(lot);
}

bool CheckSignals(int &signal)
{
   signal = 0;

   if(Bars(_Symbol, PERIOD_CURRENT) < SlowMA + 10) return false;

   double fastMA[], slowMA[], rsi[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(handleFastMA, 0, 1, 2, fastMA) < 2 ||
      CopyBuffer(handleSlowMA, 0, 1, 2, slowMA) < 2 ||
      CopyBuffer(handleRSI, 0, 1, 1, rsi) < 1) return false;

   double close_price = iClose(_Symbol, PERIOD_CURRENT, 1);

   // Simplified fast trend crossover
   if(fastMA[1] <= slowMA[1] && fastMA[0] > slowMA[0] && rsi[0] > 50) 
      signal = 1;

   if(fastMA[1] >= slowMA[1] && fastMA[0] < slowMA[0] && rsi[0] < 50) 
      signal = -1;

   // Dip/Rip logic
   if(UseDipRip)
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(handleATR, 0, 1, 1, atr) > 0)
      {
         double dip_level = slowMA[0] - atr[0] * DipMultiplier;
         double rip_level = slowMA[0] + atr[0] * RipMultiplier;
         
         if(close_price <= dip_level && rsi[0] < RSIDip) signal = 1;
         if(close_price >= rip_level && rsi[0] > RSIRip) signal = -1;
      }
   }
   
   return (signal != 0);
}

void OpenTrade(int signal)
{
   if(TradeOnlyOne && CountOurPositions() > 0) return;
   if(CooldownMinutes > 0 && TimeCurrent() - last_trade_time < CooldownMinutes * 60)
   {
      int minutes_left = (int)((CooldownMinutes * 60 - (TimeCurrent() - last_trade_time)) / 60);
      bot_status_msg = "COOLDOWN (" + IntegerToString(minutes_left) + "m)";
      return;
   }
   
   double lot = CalculateLotSize(StopLossPips);
   if(lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) return;
   
   double sl_distance = StopLossPips * pip_size;
   double tp_distance = TakeProfitPips * pip_size;
   
   double min_stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(sl_distance < min_stop_level) sl_distance = min_stop_level;
   if(tp_distance < min_stop_level) tp_distance = min_stop_level;
   
   if(signal == 1)
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = (StopLossPips > 0) ? price - sl_distance : 0;
      double tp = (TakeProfitPips > 0) ? price + tp_distance : 0;

      if(trade.Buy(lot, _Symbol, price, sl, tp, "NGU_Buy_S" + IntegerToString(martingale_step)))
      {
         last_trade_time = TimeCurrent();
         daily_trade_count++;
         Print("BUY OPENED - Lot: ", lot, " Step: ", martingale_step);
      }
   }
   else if(signal == -1)
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = (StopLossPips > 0) ? price + sl_distance : 0;
      double tp = (TakeProfitPips > 0) ? price - tp_distance : 0;

      if(trade.Sell(lot, _Symbol, price, sl, tp, "NGU_Sell_S" + IntegerToString(martingale_step)))
      {
         last_trade_time = TimeCurrent();
         daily_trade_count++;
         Print("SELL OPENED - Lot: ", lot, " Step: ", martingale_step);
      }
   }
}

void ManageTrades()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      string sym = PositionGetSymbol(i);
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      if(ticket > 0 && sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_volume = PositionGetDouble(POSITION_VOLUME);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         double current_price = (type == POSITION_TYPE_BUY)? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         double profit_pips = 0;
         if(type == POSITION_TYPE_BUY) profit_pips = (current_price - open_price) / pip_size;
         else if(type == POSITION_TYPE_SELL) profit_pips = (open_price - current_price) / pip_size;

         if(UsePartialClose && profit_pips >= PartialTPTriggerPips && current_volume > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            double close_vol = CleanAndNormalizeLot(current_volume / 2.0);
            if(close_vol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               trade.PositionClosePartial(ticket, close_vol);
            }
         }

         if(BreakEven > 0 && profit_pips >= BreakEven)
         {
            if(type == POSITION_TYPE_BUY && (sl < open_price || sl == 0)) 
               trade.PositionModify(ticket, open_price, tp);
            else if(type == POSITION_TYPE_SELL && (sl > open_price || sl == 0)) 
               trade.PositionModify(ticket, open_price, tp);
         }

         if(TrailStart > 0 && profit_pips >= TrailStart)
         {
            double new_sl;
            if(type == POSITION_TYPE_BUY)
            { 
               new_sl = current_price - TrailStep * pip_size; 
               if(sl == 0 || new_sl > sl + (pip_size * 0.5)) 
                  trade.PositionModify(ticket, new_sl, tp);
            }
            else
            { 
               new_sl = current_price + TrailStep * pip_size; 
               if(sl == 0 || new_sl < sl - (pip_size * 0.5)) 
                  trade.PositionModify(ticket, new_sl, tp);
            }
         }
      }
   }
}

void OnTick()
{
   if(!EquityProtector()) { UpdateDashboard(); return; }
   if(!CheckAllowedDays()) { UpdateDashboard(); return; }
   if(!CheckFridayFilter()) { UpdateDashboard(); return; }
   if(!CheckTradingHours()) { UpdateDashboard(); return; }
   if(!CheckSpread()) { UpdateDashboard(); return; }
   if(!IsMarketTrending()) { UpdateDashboard(); return; }
   
   ManageTrades();
   
   int signal;
   if(CheckSignals(signal)) OpenTrade(signal);

   UpdateDashboard();
}
