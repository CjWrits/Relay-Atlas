export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

class StructuredLogger {
  private level: LogLevel = 'info';

  public setLevel(level: LogLevel) {
    this.level = level;
  }

  private log(level: LogLevel, message: string, meta?: Record<string, unknown>) {
    const entry = {
      timestamp: new Date().toISOString(),
      level: level.toUpperCase(),
      message,
      ...(meta && { meta }),
    };
    if (level === 'error') {
      console.error(JSON.stringify(entry));
    } else if (level === 'warn') {
      console.warn(JSON.stringify(entry));
    } else {
      console.log(JSON.stringify(entry));
    }
  }

  public debug(msg: string, meta?: Record<string, unknown>) {
    if (this.level === 'debug') this.log('debug', msg, meta);
  }
  public info(msg: string, meta?: Record<string, unknown>) {
    this.log('info', msg, meta);
  }
  public warn(msg: string, meta?: Record<string, unknown>) {
    this.log('warn', msg, meta);
  }
  public error(msg: string, meta?: Record<string, unknown>) {
    this.log('error', msg, meta);
  }
}

export const logger = new StructuredLogger();
