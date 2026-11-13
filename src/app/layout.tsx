import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Project Relay Atlas',
  description: 'Distributed workspace synchronization and real-time backend engine',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
