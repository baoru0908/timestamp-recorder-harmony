import BuildProfile from 'BuildProfile';

/**
 * 调试日志：仅 debug 包（BuildProfile.DEBUG === true）输出，release 包静默。
 * 用于替代散落的 console.info 调试语句，避免生产环境日志噪音。
 */
export function logD(tag: string, message: string): void {
  if (BuildProfile.DEBUG) {
    console.info(`[${tag}] ${message}`);
  }
}
